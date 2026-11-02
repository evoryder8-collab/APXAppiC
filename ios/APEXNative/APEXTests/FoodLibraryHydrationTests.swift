import XCTest
@testable import APEX

final class FoodLibraryHydrationTests: XCTestCase {
    private struct Row: FoodLibraryRow, Equatable {
        let id: String
        let ownerUserID: UUID?
        var protein: Double? = nil
    }

    func testOlderOwnedAndReferencedFoodsSurviveThePublicCatalogueLimit() async throws {
        let owner = UUID(), other = UUID()
        let sample = (0..<250).map { _ in Row(id: UUID().uuidString, ownerUserID: nil) }
        let owned = (0..<54).map { _ in Row(id: UUID().uuidString, ownerUserID: owner) }
        let presetFoods = (0..<3).map { _ in Row(id: UUID().uuidString, ownerUserID: nil) }
        let favourite = Row(id: UUID().uuidString, ownerUserID: nil, protein: 12)
        let unrelated = Row(id: UUID().uuidString, ownerUserID: nil)
        let foreign = Row(id: UUID().uuidString, ownerUserID: other)
        let referenced = presetFoods + [favourite, owned[0], sample[0], foreign]
        var requests: [FoodLibraryHydration.Request] = []

        let loaded = try await FoodLibraryHydration.complete(
            initial: sample, ownerID: owner,
            referencedIDs: Set(referenced.compactMap { UUID(uuidString: $0.id) })
        ) { request in
            requests.append(request)
            XCTAssertEqual(request.ownerID, owner)
            let rows: [Row]
            switch request.scope {
            case .owned:
                rows = owned
            case .referenced(let ids):
                XCTAssertLessThanOrEqual(ids.count, 50, "Food IDs stay in bounded requests")
                rows = (presetFoods + [favourite, foreign]).filter { ids.contains(UUID(uuidString: $0.id)!) }
            }
            // A server page cap below the requested size must not drop the tail.
            return Array(rows.dropFirst(request.range.lowerBound).prefix(2))
        }

        let loadedIDs = Set(loaded.map { $0.id.lowercased() })
        XCTAssertEqual(loaded.count, 308)
        XCTAssertTrue((owned + presetFoods + [favourite]).allSatisfy { loadedIDs.contains($0.id.lowercased()) })
        XCTAssertFalse(loadedIDs.contains(foreign.id.lowercased()))
        XCTAssertFalse(loadedIDs.contains(unrelated.id.lowercased()), "Do not download the entire public catalogue")
        XCTAssertEqual(loaded.first { $0.id == favourite.id }?.protein, 12)
        XCTAssertNil(loaded.first { $0.id == owned[0].id }?.protein, "Missing nutrition remains unknown")
        XCTAssertTrue(requests.contains { $0.scope == .owned && $0.range.lowerBound == 52 })
    }

    func testReferenceBatchesDeduplicateAndLeaveUnavailableReferencesUnchanged() async throws {
        let owner = UUID(), other = UUID()
        let rows = (0..<121).map { _ in Row(id: UUID().uuidString, ownerUserID: nil) }
        let unavailableID = UUID()
        let foreign = Row(id: UUID().uuidString, ownerUserID: other)
        var requestedIDs: Set<UUID> = []
        let references = Set(rows.compactMap { UUID(uuidString: $0.id) } + [unavailableID])
        let loaded = try await FoodLibraryHydration.complete(
            initial: [rows[0], rows[0], foreign], ownerID: owner,
            referencedIDs: references
        ) { request in
            switch request.scope {
            case .owned: return []
            case .referenced(let ids):
                requestedIDs.formUnion(ids)
                XCTAssertLessThanOrEqual(ids.count, 50)
                XCTAssertFalse(ids.contains(UUID(uuidString: rows[0].id)!))
                return Array(rows.filter { ids.contains(UUID(uuidString: $0.id)!) }
                    .dropFirst(request.range.lowerBound).prefix(request.range.count))
            }
        }

        XCTAssertEqual(loaded.count, rows.count)
        XCTAssertEqual(Set(loaded.map(\.id)), Set(rows.map(\.id)))
        XCTAssertTrue(requestedIDs.contains(unavailableID))
        XCTAssertEqual(references.count, 122, "Hydration must not rewrite stored references")
    }

    func testFailedReferencePageFailsTheRefreshInsteadOfPublishingAPartialLibrary() async {
        enum Unavailable: Error { case offline }
        do {
            let _: [Row] = try await FoodLibraryHydration.complete(
                initial: [], ownerID: UUID(), referencedIDs: [UUID()]
            ) { request in
                if case .referenced = request.scope { throw Unavailable.offline }
                return []
            }
            XCTFail("A failed request must leave the existing offline library intact")
        } catch {
            XCTAssertTrue(error is Unavailable)
        }
    }
}
