import Foundation
import Supabase

enum SyncFailureDisposition: Equatable, Sendable {
    case transient
    case permanent
}

/// Only connectivity and service-availability failures belong in the retry
/// outbox. Bad input and denied writes will never heal by replaying them.
enum SyncFailurePolicy {
    static func classify(
        statusCode: Int?,
        databaseCode: String?,
        isNetworkFailure: Bool
    ) -> SyncFailureDisposition {
        if isNetworkFailure { return .transient }

        if let statusCode {
            if statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500 {
                return .transient
            }
            if (400..<500).contains(statusCode) { return .permanent }
        }

        if let databaseCode = databaseCode?.uppercased() {
            if databaseCode.hasPrefix("08")
                || databaseCode.hasPrefix("53")
                || ["57P01", "57P02", "57P03"].contains(databaseCode) {
                return .transient
            }
            if databaseCode.hasPrefix("22")
                || databaseCode.hasPrefix("23")
                || databaseCode.hasPrefix("42")
                || databaseCode.hasPrefix("PGRST") {
                return .permanent
            }
        }

        // Unknown failures remain retryable so a write is never discarded
        // unless the server has identified it as permanently invalid.
        return .transient
    }

    static func classify(_ error: Error) -> SyncFailureDisposition {
        if error is URLError { return .transient }
        if let postgrest = error as? PostgrestError {
            return classify(statusCode: nil, databaseCode: postgrest.code, isNetworkFailure: false)
        }
        if let serviceError = error as? APEXServiceError {
            switch serviceError {
            case .invalidOfflineOperation, .incompleteFood, .personaMismatch, .configurationMissing:
                return .permanent
            }
        }

        let message = error.localizedDescription.lowercased()
        let networkTerms = [
            "network connection", "not connected to the internet", "timed out",
            "could not connect", "connection lost", "offline", "dns"
        ]
        if networkTerms.contains(where: message.contains) { return .transient }

        let permanentTerms = [
            "row-level security", "permission denied", "invalid input syntax",
            "violates check constraint", "duplicate key", "foreign key constraint",
            "status code 400", "status code 401", "status code 403", "status code 404",
            "http 400", "http 401", "http 403", "http 404"
        ]
        if permanentTerms.contains(where: message.contains) { return .permanent }
        return .transient
    }
}

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

struct FailedOfflineOperation: Codable, Identifiable, Sendable {
    let id: UUID
    let operation: OfflineOperation
    let reason: String
    let failedAt: Date

    init(operation: OfflineOperation, reason: String, failedAt: Date = .now) {
        id = operation.id
        self.operation = operation
        self.reason = reason
        self.failedAt = failedAt
    }
}

struct OfflineQueueDrainReport: Equatable, Sendable {
    let succeeded: Int
    let quarantined: Int
    let paused: Bool
}

/// Replays an outbox in order. A permanent poison entry is quarantined and the
/// drain continues; a transient outage pauses the queue without losing work.
enum OfflineQueueDrainer {
    static func drain(
        _ operations: [OfflineOperation],
        replay: @Sendable (OfflineOperation) async throws -> Void,
        remove: @Sendable (OfflineOperation) async throws -> Void,
        quarantine: @Sendable (OfflineOperation, String) async throws -> Void,
        classify: @Sendable (Error) -> SyncFailureDisposition
    ) async -> OfflineQueueDrainReport {
        var succeeded = 0
        var quarantined = 0

        for operation in operations {
            do {
                try await replay(operation)
                try await remove(operation)
                succeeded += 1
            } catch {
                guard classify(error) == .permanent else {
                    return OfflineQueueDrainReport(
                        succeeded: succeeded,
                        quarantined: quarantined,
                        paused: true
                    )
                }

                do {
                    try await quarantine(operation, error.localizedDescription)
                    quarantined += 1
                } catch {
                    // If the local quarantine cannot be durably recorded, keep
                    // the original operation and stop rather than lose it.
                    return OfflineQueueDrainReport(
                        succeeded: succeeded,
                        quarantined: quarantined,
                        paused: true
                    )
                }
            }
        }

        return OfflineQueueDrainReport(
            succeeded: succeeded,
            quarantined: quarantined,
            paused: false
        )
    }
}

actor OfflineStore {
    static let shared = OfflineStore()

    private let fileManager = FileManager.default
    private let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.rootURL = base.appendingPathComponent("APEXNative", isDirectory: true)
        }
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

    func quarantine(_ operation: OfflineOperation, reason: String, for userID: UUID) throws {
        try recordFailure(operation, reason: reason, for: userID)
        try removeOperation(operation.id, for: userID)
    }

    /// Preserve diagnostics for a permanently rejected write without adding
    /// it to the retry queue that carries valid offline work.
    func recordFailure(_ operation: OfflineOperation, reason: String, for userID: UUID) throws {
        var failures = try failedOperations(for: userID)
        failures.removeAll { $0.id == operation.id }
        failures.append(FailedOfflineOperation(operation: operation, reason: reason))
        try prepareDirectory(for: userID)
        try JSONEncoder.apex.encode(failures).write(
            to: failedOutboxURL(for: userID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func failedOperations(for userID: UUID) throws -> [FailedOfflineOperation] {
        let url = failedOutboxURL(for: userID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder.apex.decode([FailedOfflineOperation].self, from: Data(contentsOf: url))
            .sorted { $0.failedAt < $1.failedAt }
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

    private func failedOutboxURL(for userID: UUID) -> URL {
        userDirectory(for: userID).appendingPathComponent("failed-outbox.json")
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
