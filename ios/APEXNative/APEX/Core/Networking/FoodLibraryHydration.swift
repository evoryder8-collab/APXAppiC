import Foundation

protocol FoodLibraryRow: Sendable {
    var id: String { get }
    var ownerUserID: UUID? { get }
}

/// A bounded public catalogue is only a starting point. Account-owned foods
/// and foods used by saved presets, preferences and history must remain usable
/// even when newer public products push them beyond that catalogue window.
enum FoodLibraryHydration {
    struct Request: Equatable, Sendable {
        enum Scope: Equatable, Sendable {
            case owned
            case referenced([UUID])
        }

        let ownerID: UUID
        let scope: Scope
        let range: ClosedRange<Int>
    }

    static func complete<Row: FoodLibraryRow>(
        initial: [Row],
        ownerID: UUID,
        referencedIDs: Set<UUID>,
        fetch: (Request) async throws -> [Row]
    ) async throws -> [Row] {
        var result: [Row] = []
        var seen: Set<String> = []
        func append(_ rows: [Row]) {
            for row in rows where row.ownerUserID == nil || row.ownerUserID == ownerID {
                if seen.insert(row.id.lowercased()).inserted { result.append(row) }
            }
        }
        append(initial)

        func load(_ scope: Request.Scope, pageSize: Int) async throws {
            var offset = 0
            while true {
                try Task.checkCancellation()
                let page = try await fetch(Request(
                    ownerID: ownerID, scope: scope,
                    range: offset ... (offset + pageSize - 1)
                ))
                guard !page.isEmpty else { return }
                append(page)
                // PostgREST can impose a smaller cap than the requested range.
                offset += page.count
            }
        }

        try await load(.owned, pageSize: 250)
        let missing = referencedIDs
            .filter { !seen.contains($0.uuidString.lowercased()) }
            .sorted { $0.uuidString < $1.uuidString }
        for offset in stride(from: 0, to: missing.count, by: 50) {
            let ids = Array(missing[offset ..< min(offset + 50, missing.count)])
            try await load(.referenced(ids), pageSize: ids.count)
        }
        return result
    }
}
