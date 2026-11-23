import Foundation
import Observation
import Supabase

/// A room as the server reports it. The identity fields never change; the
/// live ones (state, version, control, status, head count) are copied out by
/// `TrainTogetherRoom.adopt` whenever a newer version arrives.
struct TrainTogetherRoomInfo: Decodable, Sendable {
    let id: UUID
    let code: String
    let kind: TrainTogether.Kind
    let title: String
    let hostUserID: UUID
    let hostName: String
    let isHost: Bool
    let startsAt: Date
    let plan: TrainTogether.Plan
    let state: TrainTogether.State
    let version: Int
    let sharedControl: Bool
    let status: String
    let memberCount: Int
    let serverNow: Date
    /// Present on a write's reply: false when another press got there first.
    let accepted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, code, kind, title, plan, state, version, status, accepted
        case hostUserID = "host_user_id"
        case hostName = "host_name"
        case isHost = "is_host"
        case startsAt = "starts_at"
        case sharedControl = "shared_control"
        case memberCount = "member_count"
        case serverNow = "server_now"
    }
}

/// The server's refusal tokens, raised verbatim by the room functions.
enum TrainTogetherError: String, Error, Equatable {
    case premiumRequired = "premium_required"
    case notFound = "room_not_found"
    case ended = "room_ended"
    case full = "room_full"
    case tooManyAttempts = "too_many_attempts"
    case notAllowed = "not_allowed"
    case classNotAllowed = "class_not_allowed"
    case tooManyRooms = "too_many_rooms"
    case unavailable

    init(_ error: Error) {
        self = (error as? PostgrestError).flatMap { Self(rawValue: $0.message) } ?? .unavailable
    }

    var message: String {
        switch self {
        case .premiumRequired: "Train together comes with Premium."
        case .notFound: "No workout has that code. Check it with the person who sent it."
        case .ended: "This workout has ended."
        case .full: "This workout is full."
        case .tooManyAttempts: "Too many codes tried. Wait a few minutes and try again."
        case .notAllowed: "Only the host can do that."
        case .classNotAllowed: "Only a coach can open a class."
        case .tooManyRooms: "You have too many workouts open. End one first."
        case .unavailable: "Could not reach the workout. Check your connection and try again."
        }
    }
}

enum TrainTogetherCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = ExternalWorkoutImport.parseTimestamp(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: #"not a date: \#(text)"#))
        }
        return decoder
    }()

    /// Whole milliseconds written from the rounded integer, so the time a press
    /// made here is exactly the time every other phone reads back.
    static func string(_ date: Date) -> String {
        let (seconds, milliseconds) = Int64((date.timeIntervalSince1970 * 1_000).rounded())
            .quotientAndRemainder(dividingBy: 1_000)
        let whole = wholeSeconds.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        return whole.dropLast() + String(format: ".%03dZ", milliseconds)
    }

    nonisolated(unsafe) private static let wholeSeconds = ISO8601DateFormatter()
}

struct TrainTogetherPresence: Codable, Equatable, Sendable {
    struct SharedSet: Codable, Equatable, Sendable {
        var exercise: String
        var set: Int
        var reps: Int?
        var kg: Double?
        var rir: Int?
    }

    var logged: Int
    var set: SharedSet?

    /// What this person shows the room: how many sets they have logged and,
    /// only when they chose to share in a friends room, their last set.
    init(setInputs: [WorkoutSetInput], sharing: Bool) {
        logged = setInputs.filter(ExerciseLogging.isResolved).count
        set = sharing ? setInputs.last { !$0.skipped }.map {
            SharedSet(exercise: $0.exerciseName, set: $0.setNumber, reps: $0.reps, kg: $0.weightKG, rir: $0.rir)
        } : nil
    }
}

/// One phone's live connection to a room: the snapshot, its version, who is
/// here, and the server clock. Presses go through `send`; everything else is
/// derived from `state` by `timeline`.
@MainActor
@Observable
final class TrainTogetherRoom {
    let client: SupabaseClient
    let myUserID: UUID
    let timeline: TrainTogether.Timeline
    let info: TrainTogetherRoomInfo
    /// What this phone shows: the server's copy plus any press still being sent.
    private(set) var state: TrainTogether.State
    /// The last state and version the server confirmed.
    private var confirmed: TrainTogether.State
    private(set) var version: Int
    private(set) var sharedControl: Bool
    private(set) var ended: Bool
    private(set) var memberCount: Int
    private(set) var offset: TimeInterval = 0
    /// The class lobby's card: sent from the host's phone, never stored.
    private(set) var focus = 0
    private(set) var present: [UUID: TrainTogetherPresence] = [:]
    private(set) var names: [UUID: String] = [:]
    private(set) var hostAwaySince: Date?
    private(set) var lastError: TrainTogetherError?

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    @ObservationIgnored private var queued: [(action: TrainTogether.Action, time: Date)] = []
    @ObservationIgnored private var writer: Task<Void, Never>?
    @ObservationIgnored private var trackedPresence: TrainTogetherPresence?

    private struct RoomID: Encodable, Sendable { let p_id: UUID }

    private init(client: SupabaseClient, myUserID: UUID, info: TrainTogetherRoomInfo) {
        self.client = client
        self.myUserID = myUserID
        self.info = info
        state = info.state
        confirmed = info.state
        version = info.version
        sharedControl = info.sharedControl
        ended = info.status == "ended"
        memberCount = info.memberCount
        offset = info.serverNow.timeIntervalSinceNow
        timeline = TrainTogether.Timeline(
            exercises: TrainTogether.anchorRows(plan: info.plan, roomID: info.id, title: info.title, ownerID: myUserID).exercises,
            warmupText: info.plan.warmupText,
            warmupDuration: info.plan.warmupDuration
        )
    }

    var serverNow: Date { Date().addingTimeInterval(offset) }
    var isHost: Bool { info.isHost }
    var canControl: Bool { !ended && (info.isHost || (info.kind == .friends && sharedControl)) }
    var showsNames: Bool { info.isHost || info.kind == .friends }
    var hostIsHere: Bool { info.isHost || present[info.hostUserID] != nil }
    func step(at time: Date? = nil) -> TrainTogether.Step { timeline.now(state, at: time ?? serverNow) }

    // MARK: - Opening a room

    static func create(
        client: SupabaseClient, kind: TrainTogether.Kind, title: String, startsAt: Date, plan: TrainTogether.Plan
    ) async throws -> TrainTogetherRoom {
        struct Params: Encodable {
            let p_kind: String
            let p_title: String
            let p_starts_at: String
            let p_plan: AnyJSON
            let p_state: AnyJSON
        }
        let userID = try await client.auth.session.user.id
        let data: Data
        do {
            data = try await client.rpc("group_workout_create", params: Params(
                p_kind: kind.rawValue,
                p_title: title,
                p_starts_at: TrainTogetherCoding.string(startsAt),
                p_plan: try json(plan),
                p_state: try json(TrainTogether.State.lobby(at: startsAt))
            )).execute().data
        } catch {
            throw TrainTogetherError(error)
        }
        return try await opened(client: client, userID: userID, data: data)
    }

    static func join(client: SupabaseClient, code: String) async throws -> TrainTogetherRoom {
        struct Params: Encodable { let p_code: String }
        let userID = try await client.auth.session.user.id
        let data: Data
        do {
            data = try await client.rpc("group_workout_join", params: Params(p_code: code)).execute().data
        } catch {
            throw TrainTogetherError(error)
        }
        struct Refusal: Decodable { let error: String }
        if let refusal = try? JSONDecoder().decode(Refusal.self, from: data) {
            throw TrainTogetherError(rawValue: refusal.error) ?? .unavailable
        }
        return try await opened(client: client, userID: userID, data: data)
    }

    /// Whether this account may host or join, from the server's switch.
    static func access(client: SupabaseClient) async -> (allowed: Bool, canHostClass: Bool) {
        struct Reply: Decodable { let allowed: Bool; let can_host_class: Bool }
        guard let data = try? await client.rpc("train_together_my_access").execute().data,
              let reply = try? TrainTogetherCoding.decoder.decode(Reply.self, from: data) else { return (false, false) }
        return (reply.allowed, reply.can_host_class)
    }

    private static func opened(client: SupabaseClient, userID: UUID, data: Data) async throws -> TrainTogetherRoom {
        let info = try TrainTogetherCoding.decoder.decode(TrainTogetherRoomInfo.self, from: data)
        let room = TrainTogetherRoom(client: client, myUserID: userID, info: info)
        await room.measureClock()
        await room.connect()
        await room.refreshRoster()
        return room
    }

    private static func json(_ value: some Encodable) throws -> AnyJSON {
        try JSONDecoder().decode(AnyJSON.self, from: TrainTogetherCoding.encoder.encode(value))
    }

    /// One room function called with this room's id, its reply decoded.
    private func call<Reply: Decodable>(_ function: String, as _: Reply.Type) async -> Reply? {
        guard let data = try? await client.rpc(function, params: RoomID(p_id: info.id)).execute().data else { return nil }
        return try? TrainTogetherCoding.decoder.decode(Reply.self, from: data)
    }

    // MARK: - Live connection

    private func connect() async {
        // In a class, members are known to the room by a key of this visit only,
        // so they never see each other's accounts; the host keeps their own id.
        let key = info.kind == .class && !info.isHost ? UUID() : myUserID
        let channel = client.realtimeV2.channel("group:\(info.id.uuidString.lowercased())") { config in
            config.isPrivate = true
            config.presence.key = key.uuidString.lowercased()
        }
        self.channel = channel
        let states = channel.broadcastStream(event: "state")
        let endings = channel.broadcastStream(event: "ended")
        let focuses = channel.broadcastStream(event: "focus")
        let presence = channel.presenceChange()
        listeners = [
            Task { [weak self] in
                for await message in states { self?.receive(state: message) }
            },
            Task { [weak self] in
                for await _ in endings { self?.ended = true }
            },
            Task { [weak self] in
                for await message in focuses { self?.receive(focus: message) }
            },
            Task { [weak self] in
                for await change in presence { self?.receive(presence: change) }
            },
            // Broadcasts missed while the socket reconnects are healed by
            // reading the stored snapshot now and then.
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    await self?.refresh()
                }
            },
        ]
        await client.realtimeV2.connect()
        do {
            try await channel.subscribeWithError()
        } catch {
            lastError = .unavailable
        }
    }

    func close(leaving: Bool) async {
        listeners.forEach { $0.cancel() }
        listeners = []
        if let channel {
            await channel.untrack()
            await channel.unsubscribe()
        }
        channel = nil
        if leaving, !info.isHost {
            _ = try? await client.rpc("group_workout_leave", params: RoomID(p_id: info.id)).execute()
        }
    }

    func endForEveryone() async {
        guard info.isHost else { return }
        _ = try? await client.rpc("group_workout_end", params: RoomID(p_id: info.id)).execute()
        ended = true
    }

    func refresh(force: Bool = false) async {
        guard let reply = await call("group_workout_fetch", as: TrainTogetherRoomInfo.self) else { return }
        adopt(reply, force: force)
    }

    private func measureClock() async {
        var samples: [TrainTogether.ClockSample] = []
        for _ in 0..<3 {
            let sent = Date()
            guard let data = try? await client.rpc("train_together_server_now").execute().data,
                  let text = try? JSONDecoder().decode(String.self, from: data),
                  let server = ExternalWorkoutImport.parseTimestamp(text) else { continue }
            samples.append(.init(sent: sent, received: Date(), server: server))
        }
        if !samples.isEmpty { offset = TrainTogether.clockOffset(samples) }
    }

    func refreshRoster() async {
        struct Member: Decodable { let user_id: UUID; let first_name: String }
        struct Roster: Decodable { let count: Int; let members: [Member] }
        guard let roster = await call("group_workout_roster", as: Roster.self) else { return }
        memberCount = roster.count
        names = Dictionary(roster.members.map { ($0.user_id, $0.first_name) }, uniquingKeysWith: { first, _ in first })
        names[info.hostUserID] = info.hostName
    }

    // MARK: - Presses

    /// A press shows at once, then is sent as an action applied to the state
    /// the server last confirmed. One that loses to a newer press is dropped
    /// with everything queued behind it, and the phone shows the winner.
    func send(_ action: TrainTogether.Action) {
        guard canControl else { return }
        let time = serverNow
        let next = timeline.apply(action, to: state, at: time)
        guard next != state else { return }
        state = next
        queued.append((action, time))
        if writer == nil {
            writer = Task { [weak self] in await self?.drain() }
        }
    }

    private func drain() async {
        struct Params: Encodable {
            let p_id: UUID
            let p_expected_version: Int
            let p_state: AnyJSON
        }
        while !queued.isEmpty {
            let (action, time) = queued.removeFirst()
            let next = timeline.apply(action, to: confirmed, at: time)
            guard next != confirmed else { continue }
            do {
                let data = try await client.rpc("group_workout_set_state", params: Params(
                    p_id: info.id, p_expected_version: version, p_state: try Self.json(next)
                )).execute().data
                let reply = try TrainTogetherCoding.decoder.decode(TrainTogetherRoomInfo.self, from: data)
                if reply.accepted == false { queued.removeAll() }
                adopt(reply, force: true)
                lastError = nil
            } catch {
                lastError = TrainTogetherError(error)
                queued.removeAll()
                await refresh(force: true)
            }
        }
        state = confirmed
        writer = nil
    }

    func setSharedControl(_ on: Bool) {
        struct Params: Encodable { let p_id: UUID; let p_on: Bool }
        guard info.isHost, info.kind == .friends else { return }
        sharedControl = on
        Task {
            guard let data = try? await client.rpc("group_workout_set_shared_control", params: Params(p_id: info.id, p_on: on)).execute().data,
                  let reply = try? TrainTogetherCoding.decoder.decode(TrainTogetherRoomInfo.self, from: data) else { return }
            adopt(reply)
        }
    }

    /// The class host's lobby card, sent straight to the room without a write.
    func show(card index: Int) {
        guard info.isHost, info.kind == .class, state.phase == .lobby, focus != index else { return }
        focus = index
        let channel = channel
        Task { await channel?.broadcast(event: "focus", message: ["focus": .integer(index)]) }
    }

    func publish(_ presence: TrainTogetherPresence) {
        guard presence != trackedPresence, let channel else { return }
        trackedPresence = presence
        Task { try? await channel.track(presence) }
    }

    // MARK: - Arrivals

    /// `force` also takes the server's copy at an equal version, replacing a
    /// press that was shown but never confirmed. An older copy never wins.
    private func adopt(_ reply: TrainTogetherRoomInfo, force: Bool = false) {
        if reply.status == "ended" { ended = true }
        memberCount = reply.memberCount
        accept(version: reply.version, state: reply.state, sharedControl: reply.sharedControl, force: force)
    }

    private func accept(version newVersion: Int, state newState: TrainTogether.State, sharedControl control: Bool, force: Bool = false) {
        sharedControl = control
        guard newVersion > version || (force && newVersion == version) else { return }
        version = newVersion
        confirmed = newState
        if queued.isEmpty { state = newState }
    }

    private func receive(state message: JSONObject) {
        struct Event: Decodable {
            let version: Int
            let state: TrainTogether.State
            let shared_control: Bool
        }
        guard let payload = message["payload"]?.objectValue,
              let data = try? JSONEncoder().encode(payload),
              let event = try? TrainTogetherCoding.decoder.decode(Event.self, from: data) else { return }
        accept(version: event.version, state: event.state, sharedControl: event.shared_control)
    }

    private func receive(focus message: JSONObject) {
        guard !info.isHost, state.phase == .lobby,
              let index = message["payload"]?.objectValue?["focus"]?.intValue else { return }
        focus = index
    }

    private func receive(presence change: any PresenceAction) {
        for key in change.leaves.keys {
            if let id = UUID(uuidString: key) { present[id] = nil }
        }
        var unknown = false
        for (key, entry) in change.joins {
            guard let id = UUID(uuidString: key) else { continue }
            present[id] = (try? entry.decodeState(as: TrainTogetherPresence.self)) ?? TrainTogetherPresence(setInputs: [], sharing: false)
            if names[id] == nil { unknown = true }
        }
        hostAwaySince = hostIsHere ? nil : (hostAwaySince ?? .now)
        if unknown { Task { await refreshRoster() } }
    }
}
