import Foundation

enum OfflineOperationKind: String, Codable, Sendable {
    case upsert
    case delete
    case rpc
}

struct OfflineOperation: Codable, Identifiable, Sendable {
    let id: UUID
    let kind: OfflineOperationKind
    let table: String
    let payload: Data?
    let recordID: UUID?
    let onConflict: String?
    let rpcFunction: String?
    let createdAt: Date

    static func upsert<T: Encodable & Sendable>(
        _ value: T,
        table: String,
        onConflict: String?
    ) throws -> OfflineOperation {
        OfflineOperation(
            id: UUID(),
            kind: .upsert,
            table: table,
            payload: try JSONEncoder.apex.encode(value),
            recordID: nil,
            onConflict: onConflict,
            rpcFunction: nil,
            createdAt: .now
        )
    }

    static func delete(table: String, id: UUID) -> OfflineOperation {
        OfflineOperation(
            id: UUID(),
            kind: .delete,
            table: table,
            payload: nil,
            recordID: id,
            onConflict: nil,
            rpcFunction: nil,
            createdAt: .now
        )
    }

    static func rpc<T: Encodable & Sendable>(_ function: String, params: T) throws -> OfflineOperation {
        OfflineOperation(
            id: UUID(),
            kind: .rpc,
            table: "",
            payload: try JSONEncoder.apex.encode(params),
            recordID: nil,
            onConflict: nil,
            rpcFunction: function,
            createdAt: .now
        )
    }
}

actor OfflineStore {
    static let shared = OfflineStore()

    private let fileManager = FileManager.default
    private let rootURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        rootURL = base.appendingPathComponent("APEXNative", isDirectory: true)
    }

    func loadDashboard(for userID: UUID) throws -> DashboardData? {
        let url = dashboardURL(for: userID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.apex.decode(DashboardData.self, from: Data(contentsOf: url))
    }

    func saveDashboard(_ dashboard: DashboardData, for userID: UUID) throws {
        try prepareDirectory(for: userID)
        let url = dashboardURL(for: userID)
        try JSONEncoder.apex.encode(dashboard).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func enqueue(_ operation: OfflineOperation, for userID: UUID) throws {
        var operations = try pendingOperations(for: userID)
        operations.append(operation)
        try saveOperations(operations, for: userID)
    }

    func pendingOperations(for userID: UUID) throws -> [OfflineOperation] {
        let url = outboxURL(for: userID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder.apex.decode([OfflineOperation].self, from: Data(contentsOf: url))
            .sorted { $0.createdAt < $1.createdAt }
    }

    func removeOperation(_ id: UUID, for userID: UUID) throws {
        let remaining = try pendingOperations(for: userID).filter { $0.id != id }
        try saveOperations(remaining, for: userID)
    }

    private func saveOperations(_ operations: [OfflineOperation], for userID: UUID) throws {
        try prepareDirectory(for: userID)
        try JSONEncoder.apex.encode(operations).write(
            to: outboxURL(for: userID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func prepareDirectory(for userID: UUID) throws {
        let directory = userDirectory(for: userID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
    }

    private func userDirectory(for userID: UUID) -> URL {
        rootURL.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
    }

    private func dashboardURL(for userID: UUID) -> URL {
        userDirectory(for: userID).appendingPathComponent("dashboard.json")
    }

    private func outboxURL(for userID: UUID) -> URL {
        userDirectory(for: userID).appendingPathComponent("outbox.json")
    }
}

private extension JSONEncoder {
    static var apex: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var apex: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
