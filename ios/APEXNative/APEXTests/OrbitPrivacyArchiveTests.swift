import XCTest
@testable import APEX

final class OrbitPrivacyArchiveTests: XCTestCase {
    func testArchiveFiltersEveryCollectionToTheRequestedOwner() throws {
        let owner = UUID()
        let other = UUID()
        let data = DashboardData(
            orbitShoes: [shoe(userID: owner, name: "Owner pair"), shoe(userID: other, name: "Other pair")]
        )

        let archive = OrbitPrivateArchive.ownerScoped(
            from: data,
            userID: owner,
            exportedAt: "2026-08-17T00:00:00Z"
        )

        XCTAssertEqual(archive.userID, owner)
        XCTAssertEqual(archive.shoes.map(\.name), ["Owner pair"])
        XCTAssertTrue(archive.routes.isEmpty)
        XCTAssertTrue(archive.runs.isEmpty)
    }

    func testArchiveUsesWebCompatibleSnakeCaseKeys() throws {
        let owner = UUID()
        let archive = OrbitPrivateArchive.ownerScoped(
            from: DashboardData(orbitShoes: [shoe(userID: owner, name: "Pair")]),
            userID: owner,
            exportedAt: "2026-08-17T00:00:00Z"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any]
        )

        XCTAssertEqual(object["user_id"] as? String, owner.uuidString.uppercased())
        XCTAssertNotNil(object["exported_at"])
        XCTAssertNotNil(object["campaign_sessions"])
    }

    private func shoe(userID: UUID, name: String) -> OrbitShoe {
        OrbitShoe(
            id: UUID(),
            userID: userID,
            name: name,
            brand: "APEX",
            firstUseDate: "2026-08-17",
            preferredSurfaces: ["road"],
            notes: "",
            archived: false,
            createdAt: "2026-08-17T00:00:00Z",
            updatedAt: "2026-08-17T00:00:00Z"
        )
    }
}

final class SupabaseServiceReliabilityTests: XCTestCase {
    func testRealtimeSubscriptionsAreTableScopedAndIsolatedToCurrentUser() {
        let currentUser = UUID()
        let otherUser = UUID()
        let subscriptions = SupabaseService.realtimeSubscriptions(userID: currentUser)

        XCTAssertFalse(subscriptions.isEmpty)
        XCTAssertEqual(Set(subscriptions.map(\.table)).count, subscriptions.count)
        XCTAssertTrue(subscriptions.allSatisfy { !$0.table.isEmpty })
        XCTAssertTrue(subscriptions.allSatisfy { $0.filterColumn == "user_id" })
        XCTAssertTrue(subscriptions.allSatisfy { $0.filterValue == currentUser })
        XCTAssertFalse(subscriptions.contains { $0.filterValue == otherUser })
        XCTAssertTrue(subscriptions.contains { $0.table == "daily_logs" })
        XCTAssertFalse(subscriptions.contains { $0.table == "activity_types" })
        XCTAssertFalse(subscriptions.contains { $0.table == "foods" })
    }
}
