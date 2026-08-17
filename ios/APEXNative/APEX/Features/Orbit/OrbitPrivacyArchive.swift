import Foundation

struct OrbitPrivateArchive: Codable, Sendable {
    let exportedAt: String
    let userID: UUID
    let routes: [OrbitRouteRecord]
    let runs: [OrbitRunRecord]
    let shoes: [OrbitShoe]
    let segments: [OrbitSegment]
    let posters: [OrbitPoster]
    let inductions: [OrbitInduction]
    let campaigns: [OrbitCampaign]
    let campaignSessions: [OrbitCampaignSession]

    enum CodingKeys: String, CodingKey {
        case routes, runs, shoes, segments, posters, inductions, campaigns
        case exportedAt = "exported_at"
        case userID = "user_id"
        case campaignSessions = "campaign_sessions"
    }

    static func ownerScoped(from data: DashboardData, userID: UUID, exportedAt: String = Date().ISO8601Format()) -> Self {
        Self(
            exportedAt: exportedAt,
            userID: userID,
            routes: data.orbitRoutes.filter { $0.userID == userID },
            runs: data.orbitRuns.filter { $0.userID == userID },
            shoes: data.orbitShoes.filter { $0.userID == userID },
            segments: data.orbitSegments.filter { $0.userID == userID },
            posters: data.orbitPosters.filter { $0.userID == userID },
            inductions: data.orbitInductions.filter { $0.userID == userID },
            campaigns: data.orbitCampaigns.filter { $0.userID == userID },
            campaignSessions: data.orbitCampaignSessions.filter { $0.userID == userID }
        )
    }

    func writeTemporaryFile() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apex-orbit-\(Date().apexDateKey).json")
        try encoder.encode(self).write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return url
    }
}
