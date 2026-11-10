/*
 * Golden parity for ProgressPhotoEngine and ProgressComparison against
 * src/lib/progressPhoto.ts and src/lib/progressComparison.ts.
 */
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import APEX

private struct ProgressFixture: Decodable {
    let photos: [PhotoRow]
    let fit_within: [FitCase]
    let normalize_crop: [CropCase]
    let comparison_view: [ViewCase]
    let zoom: [ZoomCase]
    let update_views: [UpdateCase]
    let cover_crop: [CoverCase]
    let comparison_ratio: [RatioCase]
    let framing: [FramingCase]
    let capture_ratio: [CaptureCase]
    let days_between: [DaysCase]
    let prefer_same_pose: [UUID]
    let snapshot_for_date: [SnapshotCase]
    let storage_paths: PathRow
    let poster_content: [PosterCase]
    let strength: [StrengthCase]
    let sessions: [SessionRow]
    let logs: [LogRow]
}

private struct PhotoRow: Decodable {
    let id: UUID; let local_date: String; let pose: String
    let aspect_ratio: Double; let client_idempotency_key: String
}
private struct FitCase: Decodable { let w: Double; let h: Double; let maxW: Double; let maxH: Double; let expected: FitRow }
private struct FitRow: Decodable { let width: Int; let height: Int; let scale: Double }
private struct CropCase: Decodable { let x: Double; let y: Double; let scale: Double; let expected: CropRow }
private struct CropRow: Decodable { let x: Double; let y: Double; let scale: Double }
private struct ViewRow: Decodable { let scale: Double; let x: Double; let y: Double }
private struct ViewCase: Decodable { let input: ViewRow; let expected: ViewRow }
private struct ZoomCase: Decodable { let from: ViewRow; let delta: Double; let expected: ViewRow }
private struct UpdateCase: Decodable { let synced: Bool; let expected: ViewsRow }
private struct ViewsRow: Decodable { let left: ViewRow; let right: ViewRow }
private struct CoverCase: Decodable { let w: Double; let h: Double; let ratio: Double; let expected: CoverRow }
private struct CoverRow: Decodable { let sx: Double; let sy: Double; let width: Double; let height: Double }
private struct RatioCase: Decodable { let a: UUID; let b: UUID; let expected: Double }
private struct FramingCase: Decodable { let id: UUID; let expected: String }
private struct CaptureCase: Decodable { let mode: String; let preview: Double; let expected: Double }
private struct DaysCase: Decodable { let a: UUID; let b: UUID; let expected: Int }
private struct SnapshotCase: Decodable { let date: String; let expected: String? }
private struct PathRow: Decodable { let full: String; let thumbnail: String }
private struct PosterCase: Decodable { let mode: String; let expected: PosterRow }
private struct PosterRow: Decodable { let stats: Bool; let athlete: Bool; let pose: Bool; let privateFooter: Bool }
private struct StrengthCase: Decodable { let first: String; let second: String; let expected: StrengthRow }
private struct StrengthRow: Decodable { let averageLoadDeltaKg: Double?; let matchedExercises: Int; let loadedSets: Int }
private struct SessionRow: Decodable { let id: String; let date: String; let completed: Bool }
private struct LogRow: Decodable {
    let id: String; let session_id: String; let exercise_id: String?
    let exercise_name: String; let weight_kg: Double?; let skipped: Bool
}

final class ProgressParityTests: XCTestCase {
    private static let fixture: ProgressFixture = {
        guard let url = Bundle(for: ProgressParityTests.self)
            .url(forResource: "progress-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("progress-parity.json missing from the test bundle")
        }
        return try! JSONDecoder().decode(ProgressFixture.self, from: data)
    }()

    /* String ids in the fixture are not UUIDs, so they are mapped to stable
       ones here; only ordering and grouping depend on their identity. The
       namespace user is fixed on purpose: seeding it with a fresh UUID gives
       the same name a different id on every call, which silently defeats the
       grouping this suite exists to check. */
    private static let fixtureNamespace = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!

    private func stableID(_ raw: String) -> UUID {
        APEXStableID.scopedUUID(namespace: "fixture", date: raw, userID: Self.fixtureNamespace)
    }

    private func photo(_ row: PhotoRow) -> ProgressPhoto {
        ProgressPhoto(
            id: row.id, userID: UUID(), localDate: row.local_date,
            capturedAt: "\(row.local_date)T09:00:00.000Z", pose: row.pose,
            storagePath: "", thumbnailPath: "", width: 1080, height: 1620,
            aspectRatio: row.aspect_ratio, cropX: 0.5, cropY: 0.5, cropScale: 1,
            referencePhotoID: nil, weightKG: nil, note: "",
            clientIdempotencyKey: row.client_idempotency_key
        )
    }

    private var photos: [ProgressPhoto] { Self.fixture.photos.map(photo) }

    func testGeometryMatchesTheWeb() {
        for scenario in Self.fixture.fit_within {
            let fitted = ProgressPhotoEngine.fitWithin(
                width: scenario.w, height: scenario.h,
                maxWidth: scenario.maxW, maxHeight: scenario.maxH
            )
            XCTAssertEqual(fitted?.width, scenario.expected.width)
            XCTAssertEqual(fitted?.height, scenario.expected.height)
            XCTAssertEqual(fitted?.scale ?? .nan, scenario.expected.scale, accuracy: 0.0001)
        }
        for scenario in Self.fixture.normalize_crop {
            let crop = ProgressPhotoEngine.normalizeCrop(x: scenario.x, y: scenario.y, scale: scenario.scale)
            XCTAssertEqual(crop.x, scenario.expected.x, accuracy: 0.0001)
            XCTAssertEqual(crop.y, scenario.expected.y, accuracy: 0.0001)
            XCTAssertEqual(crop.scale, scenario.expected.scale, accuracy: 0.0001)
        }
        for scenario in Self.fixture.cover_crop {
            let crop = ProgressPhotoEngine.coverCrop(
                width: scenario.w, height: scenario.h, targetAspectRatio: scenario.ratio
            )
            XCTAssertEqual(crop?.sx ?? .nan, scenario.expected.sx, accuracy: 0.0001)
            XCTAssertEqual(crop?.sy ?? .nan, scenario.expected.sy, accuracy: 0.0001)
            XCTAssertEqual(crop?.width ?? .nan, scenario.expected.width, accuracy: 0.0001)
            XCTAssertEqual(crop?.height ?? .nan, scenario.expected.height, accuracy: 0.0001)
        }
    }

    func testComparisonViewsMatchTheWeb() {
        for scenario in Self.fixture.comparison_view {
            let view = ProgressPhotoEngine.normalizeComparisonView(
                .init(scale: scenario.input.scale, x: scenario.input.x, y: scenario.input.y)
            )
            XCTAssertEqual(view.scale, scenario.expected.scale, accuracy: 0.0001)
            XCTAssertEqual(view.x, scenario.expected.x, accuracy: 0.0001)
            XCTAssertEqual(view.y, scenario.expected.y, accuracy: 0.0001)
        }
        for scenario in Self.fixture.zoom {
            let view = ProgressPhotoEngine.zoom(
                .init(scale: scenario.from.scale, x: scenario.from.x, y: scenario.from.y),
                by: scenario.delta
            )
            XCTAssertEqual(view.scale, scenario.expected.scale, accuracy: 0.0001)
        }
        for scenario in Self.fixture.update_views {
            let views = ProgressPhotoEngine.updateViews(
                .init(left: .init(scale: 1, x: 0, y: 0), right: .init(scale: 1, x: 0, y: 0)),
                side: .left,
                view: .init(scale: 2, x: 10, y: -10),
                synced: scenario.synced
            )
            XCTAssertEqual(views.left.scale, scenario.expected.left.scale, accuracy: 0.0001)
            XCTAssertEqual(views.right.scale, scenario.expected.right.scale, accuracy: 0.0001, "synced \(scenario.synced)")
        }
    }

    func testPhotoSelectionMatchesTheWeb() {
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        for scenario in Self.fixture.comparison_ratio {
            guard let a = byID[scenario.a], let b = byID[scenario.b] else { return XCTFail("missing photo") }
            XCTAssertEqual(ProgressPhotoEngine.comparisonAspectRatio(a, b), scenario.expected, accuracy: 0.0001)
        }
        for scenario in Self.fixture.framing {
            guard let value = byID[scenario.id] else { return XCTFail("missing photo") }
            XCTAssertEqual(ProgressPhotoEngine.framingMode(value).rawValue, scenario.expected)
        }
        for scenario in Self.fixture.capture_ratio {
            guard let mode = ProgressPhotoEngine.FramingMode(rawValue: scenario.mode) else { return XCTFail("bad mode") }
            XCTAssertEqual(
                ProgressPhotoEngine.captureAspectRatio(mode, previewAspectRatio: scenario.preview),
                scenario.expected, accuracy: 0.0001, scenario.mode
            )
        }
        for scenario in Self.fixture.days_between {
            guard let a = byID[scenario.a], let b = byID[scenario.b] else { return XCTFail("missing photo") }
            XCTAssertEqual(ProgressPhotoEngine.daysBetween(a, b), scenario.expected)
        }
        guard let reference = byID[Self.fixture.photos[0].id] else { return XCTFail("missing reference") }
        XCTAssertEqual(
            ProgressPhotoEngine.preferSamePose(reference: reference, photos: photos).map(\.id),
            Self.fixture.prefer_same_pose,
            "same pose first, then most recent"
        )
    }

    /// C4. The ghost has to be the same pose, or nothing.
    func testTheGhostIsTheLatestPhotoOfTheSamePoseOrNothing() {
        let owner = UUID()
        func row(_ pose: String, _ date: String, key: String = "ios-progress-1", user: UUID? = nil) -> ProgressPhoto {
            ProgressPhoto(
                id: UUID(), userID: user ?? owner, localDate: date, capturedAt: "\(date)T07:00:00Z", pose: pose,
                storagePath: "a", thumbnailPath: "b", width: 3, height: 4, aspectRatio: 0.75,
                cropX: 0.5, cropY: 0.5, cropScale: 1, referencePhotoID: nil, weightKG: nil, note: "",
                clientIdempotencyKey: key
            )
        }
        func reference(
            _ pose: String, _ photos: [ProgressPhoto], framing: ProgressPhotoEngine.FramingMode = .full
        ) -> ProgressPhoto? {
            ProgressPhotoEngine.reference(pose: pose, framing: framing, photos: photos, ownerID: owner)
        }

        let front = row("front", "2026-10-01")
        XCTAssertNil(reference("side", [front]), "a front photo must never ghost a side shot")
        XCTAssertNil(reference("back", [front]))
        XCTAssertEqual(reference("front", [front])?.id, front.id)
        XCTAssertNil(reference("front", []))

        let olderFront = row("front", "2026-08-01")
        let side = row("side", "2026-10-05")
        XCTAssertEqual(reference("front", [olderFront, side, front])?.id, front.id, "the most recent of the pose")
        XCTAssertEqual(reference("side", [olderFront, side, front])?.id, side.id)

        /* The outline for a torso shot is a different shape, so a torso photo
           is the better ghost for one even when a full-body photo is newer. */
        let torso = row("front", "2026-09-01", key: "framing:torso:1")
        XCTAssertEqual(reference("front", [front, torso, olderFront], framing: .torso)?.id, torso.id)
        XCTAssertEqual(reference("front", [front, torso, olderFront], framing: .full)?.id, front.id)
        XCTAssertEqual(reference("front", [front, torso], framing: .free)?.id, front.id, "same pose still beats nothing")

        let stranger = row("side", "2026-11-01", user: UUID())
        XCTAssertNil(reference("side", [front, stranger]), "another account's photo is never a ghost")
    }

    /// C5. The framing chosen in the camera has no column of its own. It is
    /// carried in the row's key, which is where every reader looks for it.
    func testASavedPhotoKeepsTheFramingItWasTakenWith() throws {
        let owner = UUID()
        func saved(_ framing: ProgressPhotoEngine.FramingMode) -> ProgressPhoto {
            ProgressPhotoEngine.checkpoint(
                id: UUID(), userID: owner, takenAt: Date(timeIntervalSince1970: 1_790_000_000), pose: "front",
                framing: framing, width: 1200, height: 1500, referencePhotoID: nil, weightKG: 71.5,
                note: "  after training \n"
            )
        }
        for framing in ProgressPhotoEngine.FramingMode.allCases {
            XCTAssertEqual(ProgressPhotoEngine.framingMode(saved(framing)), framing, framing.rawValue)
        }
        XCTAssertNotEqual(
            saved(.torso).clientIdempotencyKey, saved(.torso).clientIdempotencyKey,
            "two photos must never share a key, or the second replaces the first"
        )
        let row = saved(.torso)
        XCTAssertEqual(row.userID, owner)
        XCTAssertEqual(row.aspectRatio, 0.8, accuracy: 0.0001)
        XCTAssertEqual(row.note, "after training")
        XCTAssertEqual(row.weightKG, 71.5)
        XCTAssertTrue(row.storagePath.hasPrefix(owner.uuidString.lowercased() + "/"))
    }

    /// C5. A torso photo keeps the sensor's full width, so it is a little
    /// shorter than the preview. Its ghost is drawn that much smaller, or it
    /// would sit larger than the live picture it is meant to line up with.
    func testATorsoGhostIsDrawnAtTheSizeItWasTaken() {
        func row(key: String, aspectRatio: Double) -> ProgressPhoto {
            ProgressPhoto(
                id: UUID(), userID: UUID(), localDate: "2026-10-01", capturedAt: "2026-10-01T07:00:00Z",
                pose: "front", storagePath: "a", thumbnailPath: "b", width: 4, height: 5,
                aspectRatio: aspectRatio, cropX: 0.5, cropY: 0.5, cropScale: 1, referencePhotoID: nil,
                weightKG: nil, note: "", clientIdempotencyKey: key
            )
        }
        XCTAssertEqual(ProgressPhotoEngine.ghostScale(row(key: "framing:torso:1", aspectRatio: 0.8)), 0.9375, accuracy: 0.0001)
        XCTAssertEqual(ProgressPhotoEngine.ghostScale(row(key: "framing:full:1", aspectRatio: 0.46)), 1)
        XCTAssertEqual(ProgressPhotoEngine.ghostScale(row(key: "ios-progress-1", aspectRatio: 0.75)), 1)
        XCTAssertEqual(ProgressPhotoEngine.ghostScale(row(key: "framing:torso:1", aspectRatio: 0.6)), 1, "never enlarged")
    }

    /// A small JPEG, stamped the way a camera stamps the moment it was taken.
    private func jpeg(takenAt stamp: String?) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 16)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 16))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        var properties: [CFString: Any] = [:]
        if let stamp {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: stamp]
        }
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// C6. A baseline imported from the library belongs on the day it was
    /// taken. Filed under today, every "days apart" and BEFORE/AFTER built on
    /// it is wrong.
    func testAnImportedPhotoIsFiledUnderTheDayItWasTaken() throws {
        let now = try XCTUnwrap(APEXDateMath.date(from: "2026-11-10"))
        let taken = try XCTUnwrap(
            ProgressPhotoEngine.takenAt(imageData: try jpeg(takenAt: "2025:06:14 08:30:00"), now: now),
            "the date the file carries was not read"
        )
        XCTAssertEqual(taken.apexDateKey, "2025-06-14")

        let owner = UUID()
        func row(_ date: Date) -> ProgressPhoto {
            ProgressPhotoEngine.checkpoint(
                id: UUID(), userID: owner, takenAt: date, pose: "front", framing: .full,
                width: 3, height: 4, referencePhotoID: nil, weightKG: nil, note: ""
            )
        }
        let imported = row(taken)
        XCTAssertEqual(imported.localDate, "2025-06-14")
        XCTAssertTrue(imported.storagePath.contains("/2025-06/"))
        XCTAssertEqual(ProgressPhotoEngine.daysBetween(imported, row(now)), 514)
        XCTAssertTrue(
            ProgressPhotoEngine.moment(imported, language: .english).contains("14 Jun 2025"),
            ProgressPhotoEngine.moment(imported, language: .english)
        )

        /* Today is the answer only when the file does not know better. */
        XCTAssertNil(ProgressPhotoEngine.takenAt(imageData: try jpeg(takenAt: nil), now: now))
        XCTAssertNil(ProgressPhotoEngine.takenAt(imageData: Data("not a picture".utf8), now: now))
        XCTAssertNil(ProgressPhotoEngine.takenAt(imageData: try jpeg(takenAt: "not a date"), now: now))
        XCTAssertNil(
            ProgressPhotoEngine.takenAt(imageData: try jpeg(takenAt: "2031:01:01 09:00:00"), now: now),
            "a camera clock set in the future must not file a photo after today"
        )
    }

    /// C7. A drag reports the finger's travel since it landed, again and
    /// again. The photo has to end up that far from where it started, however
    /// many reports there were, and never further than its zoom allows.
    func testADraggedPhotoFollowsTheFingerAndStopsAtItsLimit() {
        let pane = CGSize(width: 180, height: 400)
        let zoomed = ProgressPhotoEngine.ComparisonView(scale: 2, x: 0, y: 0)
        let start = ProgressPhotoEngine.ComparisonViews(left: zoomed, right: zoomed)

        var views = start
        for travel in 1...20 {
            views = ProgressPhotoEngine.drag(
                from: start, side: .left,
                translation: CGSize(width: Double(travel), height: Double(-travel)), pane: pane, synced: true
            )
        }
        let offset = ProgressPhotoEngine.panOffset(views.left, in: pane)
        XCTAssertEqual(offset.width, 20, accuracy: 0.01, "the photo did not move as far as the finger")
        XCTAssertEqual(offset.height, -20, accuracy: 0.01, "the photo did not move as far as the finger")
        XCTAssertEqual(views.right, views.left, "synced moves both photos together")

        let once = ProgressPhotoEngine.drag(
            from: start, side: .left, translation: CGSize(width: 20, height: -20), pane: pane, synced: true
        )
        XCTAssertEqual(views, once, "twenty small reports and one large one are the same drag")

        /* At twice the size a photo may travel 22 percent of its pane. */
        let thrown = ProgressPhotoEngine.drag(
            from: start, side: .left, translation: CGSize(width: 900, height: 0), pane: pane, synced: true
        )
        XCTAssertEqual(ProgressPhotoEngine.panOffset(thrown.left, in: pane).width, 0.22 * 180, accuracy: 0.01)

        let unlocked = ProgressPhotoEngine.drag(
            from: start, side: .right, translation: CGSize(width: 18, height: 0), pane: pane, synced: false
        )
        XCTAssertEqual(unlocked.left, zoomed, "unlocked leaves the untouched side alone")
        XCTAssertEqual(unlocked.right.x, 10, accuracy: 0.01, "the pan is kept as a share of the pane")
    }

    /// C7. The pan is one number read by the screen and by the exported card.
    /// On two panes of different sizes it has to be the same share of each.
    func testAPanIsTheSameShareOfTheScreenPaneAndTheExportedPane() {
        let view = ProgressPhotoEngine.ComparisonView(scale: 2, x: 10, y: -5)
        let screen = ProgressPhotoEngine.panOffset(view, in: CGSize(width: 180, height: 400))
        let card = ProgressPhotoEngine.panOffset(view, in: CGSize(width: 504, height: 1278))
        XCTAssertEqual(screen.width / 180, 0.10, accuracy: 0.0001)
        XCTAssertEqual(card.width / 504, 0.10, accuracy: 0.0001)
        XCTAssertEqual(screen.height / 400, -0.05, accuracy: 0.0001)
        XCTAssertEqual(card.height / 1278, -0.05, accuracy: 0.0001)
    }

    /// C7. Unlocked, the zoom buttons act on the side last touched.
    func testUnlockedZoomChangesOnlyTheTouchedSide() {
        let plain = ProgressPhotoEngine.ComparisonView(scale: 1, x: 0, y: 0)
        let start = ProgressPhotoEngine.ComparisonViews(left: plain, right: plain)

        let right = ProgressPhotoEngine.zoom(start, side: .right, by: 0.25, synced: false)
        XCTAssertEqual(right.right.scale, 1.25, accuracy: 0.0001)
        XCTAssertEqual(right.left, plain, "zooming the right photo overwrote the left one")

        let left = ProgressPhotoEngine.zoom(right, side: .left, by: 0.5, synced: false)
        XCTAssertEqual(left.left.scale, 1.5, accuracy: 0.0001)
        XCTAssertEqual(left.right.scale, 1.25, accuracy: 0.0001, "zooming the left photo overwrote the right one")

        let both = ProgressPhotoEngine.zoom(left, side: .right, by: 0.25, synced: true)
        XCTAssertEqual(both.left, both.right, "synced zooms both photos together")
        XCTAssertEqual(both.right.scale, 1.5, accuracy: 0.0001)
    }

    /// A comparison must never borrow a score recorded after the photo.
    func testSnapshotNeverComesFromTheFuture() {
        let snapshots = [("2026-05-01", 4.0), ("2026-06-20", 6.0), ("2026-09-01", 9.0)].map { date, level in
            RPGSnapshot(
                id: UUID(), userID: UUID(), date: date, overall: level,
                health: level, joint: level, flexibility: level,
                endurance: level, strength: level,
                strengthUpper: level, strengthLower: level
            )
        }
        for scenario in Self.fixture.snapshot_for_date {
            let found = ProgressPhotoEngine.snapshot(for: scenario.date, snapshots: snapshots)
            XCTAssertEqual(found?.date, scenario.expected, scenario.date)
        }
    }

    /// Both clients must write a photo to the same place or neither finds the
    /// other's file.
    func testStoragePathsMatchTheWeb() {
        let user = UUID(uuidString: "99999999-0000-4000-8000-000000000001")!
        let photoID = UUID(uuidString: "44444444-0000-4000-8000-000000000001")!
        let paths = ProgressPhotoEngine.storagePaths(userID: user, photoID: photoID)
        XCTAssertEqual(paths?.full, Self.fixture.storage_paths.full)
        XCTAssertEqual(paths?.thumbnail, Self.fixture.storage_paths.thumbnail)
    }

    func testExportModeAndPosterContentMatchTheWeb() {
        XCTAssertEqual(ProgressComparison.resolveExportMode(.string("minimal")), .minimal)
        XCTAssertEqual(ProgressComparison.resolveExportMode(.string("detailed")), .detailed)
        XCTAssertEqual(ProgressComparison.resolveExportMode(.string("nonsense")), .detailed)
        XCTAssertEqual(ProgressComparison.resolveExportMode(nil), .detailed)
        for scenario in Self.fixture.poster_content {
            guard let mode = ProgressComparison.ExportMode(rawValue: scenario.mode) else { return XCTFail("bad mode") }
            let content = ProgressComparison.posterContent(mode)
            XCTAssertEqual(content.stats, scenario.expected.stats, scenario.mode)
            XCTAssertEqual(content.privateFooter, scenario.expected.privateFooter, scenario.mode)
        }
    }

    func testStrengthComparisonMatchesTheWeb() {
        var sessionIDs: [String: UUID] = [:]
        let sessions = Self.fixture.sessions.map { row -> WorkoutSession in
            let id = stableID(row.id)
            sessionIDs[row.id] = id
            return WorkoutSession(
                id: id, userID: UUID(), date: row.date, programDayID: UUID(),
                isLite: false, isDeload: false, isEventRecovery: false,
                completed: row.completed, qualityScore: 1,
                startedAt: nil, completedAt: nil, notes: ""
            )
        }
        let logs = Self.fixture.logs.map { row in
            WorkoutLog(
                id: UUID(), userID: UUID(), sessionID: sessionIDs[row.session_id] ?? UUID(),
                exerciseID: row.exercise_id.map { stableID($0) },
                exerciseName: row.exercise_name, setNumber: 1,
                weightKG: row.weight_kg, reps: 8, rir: nil, skipped: row.skipped,
                overrideFlag: false, createdAt: "2026-06-01T12:00:00.000Z"
            )
        }
        for scenario in Self.fixture.strength {
            let result = ProgressComparison.strength(
                sessions: sessions, logs: logs,
                firstDate: scenario.first, secondDate: scenario.second
            )
            XCTAssertEqual(result.matchedExercises, scenario.expected.matchedExercises, "\(scenario.first)..\(scenario.second)")
            XCTAssertEqual(result.loadedSets, scenario.expected.loadedSets, "\(scenario.first)..\(scenario.second)")
            XCTAssertEqual(result.averageLoadDeltaKG == nil, scenario.expected.averageLoadDeltaKg == nil)
            if let expected = scenario.expected.averageLoadDeltaKg {
                XCTAssertEqual(result.averageLoadDeltaKG ?? .nan, expected, accuracy: 0.0001)
            }
        }
    }

    /// The concrete progress-photo service cannot currently be suspended by a
    /// test double. This source contract therefore protects the real mutation
    /// boundary: an upload begun by account A may not append its private row to
    /// account B after an auth transition.
    func testProgressPhotoUploadRejectsLateRemoteCompletionFromAnotherAccount() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(source.range(of: "func saveProgressPhoto("))
        let end = try XCTUnwrap(
            source.range(of: "func signedProgressURL(", range: start.upperBound..<source.endIndex)
        )
        let save = String(source[start.lowerBound..<end.lowerBound])
        let leaseArgument = try XCTUnwrap(
            save.range(of: "operation: AccountOperationLease"),
            "require the account lease captured synchronously by the save button"
        )
        let rowOwner = try XCTUnwrap(
            save.range(of: "userID: operation.ownerID"),
            "bind the photo row to the verified owner"
        )
        let remoteCall = try XCTUnwrap(save.range(of: "try await service.uploadProgressPhoto("))
        let revalidation = try XCTUnwrap(
            save.range(of: "try requireCurrentAccountOperation(operation)", range: remoteCall.upperBound..<save.endIndex),
            "reject the upload completion after either an owner or generation change"
        )
        let publication = try XCTUnwrap(save.range(of: "data.progressPhotos.insert(row, at: 0)"))

        XCTAssertLessThan(leaseArgument.lowerBound, remoteCall.lowerBound)
        XCTAssertLessThan(rowOwner.lowerBound, remoteCall.lowerBound)
        XCTAssertLessThan(remoteCall.lowerBound, revalidation.lowerBound)
        XCTAssertLessThan(revalidation.lowerBound, publication.lowerBound)
        XCTAssertTrue(save.contains("catch {\n                try requireCurrentAccountOperation(operation)"))

        let view = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Avatar/VisualProgressView.swift")
        )
        let button = try XCTUnwrap(view.range(of: "Save private checkpoint"))
        let actionStart = try XCTUnwrap(
            view.range(
                of: "Button {",
                options: .backwards,
                range: view.startIndex..<button.lowerBound
            )
        )
        let action = String(view[actionStart.lowerBound..<button.lowerBound])
        XCTAssertTrue(action.contains("session.accountOperationLease()"))
    }

    func testProgressPhotoPreparationCannotRepublishAPrivateImageAfterOwnerChange() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Avatar/VisualProgressView.swift")
        )
        let changeStart = try XCTUnwrap(source.range(of: ".onChange(of: selectedItem)"))
        let changeEnd = try XCTUnwrap(
            source.range(
                of: ".onChange(of: session.profile?.userID)",
                range: changeStart.upperBound..<source.endIndex
            )
        )
        let selection = String(source[changeStart.lowerBound..<changeEnd.lowerBound])
        let lease = try XCTUnwrap(
            selection.range(of: "session.accountOperationLease()"),
            "capture the owner before asynchronous PhotosPicker preparation"
        )
        let task = try XCTUnwrap(selection.range(of: "Task {"))

        XCTAssertLessThan(lease.lowerBound, task.lowerBound)
        XCTAssertTrue(selection.contains("prepareSelectedImage("))

        let helperStart = try XCTUnwrap(source.range(of: "private func prepareSelectedImage("))
        let helperEnd = try XCTUnwrap(
            source.range(
                of: "private func save(",
                range: helperStart.upperBound..<source.endIndex
            )
        )
        let helper = String(source[helperStart.lowerBound..<helperEnd.lowerBound])
        let transfer = try XCTUnwrap(helper.range(of: "loadTransferable(type: Data.self)"))
        let leaseCheck = try XCTUnwrap(
            helper.range(
                of: "session.accountOperationIsCurrent(operation)",
                range: transfer.upperBound..<helper.endIndex
            )
        )
        let publication = try XCTUnwrap(helper.range(of: "selectedImage = image"))

        XCTAssertLessThan(transfer.lowerBound, leaseCheck.lowerBound)
        XCTAssertLessThan(leaseCheck.lowerBound, publication.lowerBound)
        XCTAssertTrue(helper.contains("preparationID == requestID"))
        XCTAssertTrue(source.contains("preparationTask?.cancel()"))
    }

    func testEveryPrivateProgressImageReadCarriesAndRevalidatesItsAccountLease() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let session = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(session.range(of: "func signedProgressURL("))
        let end = try XCTUnwrap(
            session.range(of: "func completeWorkout(", range: start.upperBound..<session.endIndex)
        )
        let signedURL = String(session[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(signedURL.contains("operation: AccountOperationLease"))
        XCTAssertTrue(signedURL.contains("photo.userID == operation.ownerID"))
        XCTAssertGreaterThanOrEqual(
            signedURL.components(separatedBy: "requireCurrentAccountOperation(operation)").count - 1,
            2
        )

        let paths = [
            ("APEX/Features/Avatar/VisualProgressView.swift", "session.accountOperationLease()"),
            ("APEX/Features/Avatar/ProgressCameraView.swift", "operation: AccountOperationLease"),
            ("APEX/Features/Avatar/ProgressComparisonView.swift", "session.accountOperationLease()")
        ]
        for (path, captureToken) in paths {
            let source = try String(contentsOf: nativeRoot.appending(path: path))
            XCTAssertTrue(source.contains(captureToken), path)
            XCTAssertTrue(source.contains("operation: operation"), path)
            XCTAssertTrue(source.contains("session.accountOperationIsCurrent(operation)"), path)
        }
    }

    func testAccountBoundaryDismissesEveryPrivateProgressCaptureAndComparisonSurface() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Avatar/VisualProgressView.swift")
        )
        let start = try XCTUnwrap(source.range(of: ".onChange(of: session.profile?.userID)"))
        let end = try XCTUnwrap(
            source.range(of: ".apexPopover", range: start.upperBound..<source.endIndex)
        )
        let boundary = String(source[start.lowerBound..<end.lowerBound])
        for reset in [
            "showBriefing = false",
            "captureIntent = nil",
            "captureOperation = nil",
            "showComparison = false",
            "comparisonSelection = []",
            "showCamera = false"
        ] {
            XCTAssertTrue(boundary.contains(reset), reset)
        }
        XCTAssertTrue(source.contains("session.accountOperationIsCurrent(operation)"))
    }

    func testProgressCameraStopRevokesAPendingStartAndPhotoCallback() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Avatar/ProgressCameraView.swift")
        )
        let controllerStart = try XCTUnwrap(source.range(of: "final class ProgressCameraController"))
        let controllerEnd = try XCTUnwrap(
            source.range(of: "extension ProgressCameraController: AVCaptureDataOutputSynchronizerDelegate")
        )
        let controller = String(source[controllerStart.lowerBound..<controllerEnd.lowerBound])
        let startStart = try XCTUnwrap(controller.range(of: "func start("))
        let stopStart = try XCTUnwrap(
            controller.range(of: "func stop()", range: startStart.upperBound..<controller.endIndex)
        )
        let start = String(controller[startStart.lowerBound..<stopStart.lowerBound])
        let stop = String(controller[stopStart.lowerBound..<controller.endIndex])

        let permission = try XCTUnwrap(start.range(of: "AVCaptureDevice.requestAccess(for: .video)"))
        let cancellation = try XCTUnwrap(
            start.range(of: "Task.isCancelled == false", range: permission.upperBound..<start.endIndex),
            "a dismissed SwiftUI task must not start the camera after permission returns"
        )
        let generationCheck = try XCTUnwrap(
            start.range(of: "lifecycleGeneration == requestGeneration", range: permission.upperBound..<start.endIndex),
            "stop must revoke a pending start even when AVFoundation ignores task cancellation"
        )
        let queuedStart = try XCTUnwrap(start.range(of: "await withCheckedContinuation"))
        let postQueueGenerationCheck = try XCTUnwrap(
            start.range(
                of: "lifecycleGeneration == requestGeneration",
                range: queuedStart.upperBound..<start.endIndex
            ),
            "stop may run while session.startRunning is queued, so readiness needs a second generation check"
        )
        let ready = try XCTUnwrap(start.range(of: "isReady = true"))

        XCTAssertLessThan(permission.lowerBound, cancellation.lowerBound)
        XCTAssertLessThan(permission.lowerBound, generationCheck.lowerBound)
        XCTAssertLessThan(queuedStart.lowerBound, postQueueGenerationCheck.lowerBound)
        XCTAssertLessThan(postQueueGenerationCheck.lowerBound, ready.lowerBound)
        XCTAssertTrue(stop.contains("lifecycleGeneration &+= 1"))
        XCTAssertTrue(stop.contains("captured = nil"), "closing the camera must discard an in-flight private photo")
    }

    func testClosedProgressCaptureCannotRepublishItsPrivateImage() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Avatar/VisualProgressView.swift")
        )
        XCTAssertTrue(source.contains("@State private var captureRequestID: UUID?"))

        let coverStart = try XCTUnwrap(
            source.range(
                of: ".fullScreenCover(item: capturePresentation, onDismiss: revokeCapturePresentation)"
            ),
            "every system or interactive dismissal must synchronously revoke the capture lease"
        )
        let coverEnd = try XCTUnwrap(
            source.range(
                of: ".fullScreenCover(isPresented: $showComparison)",
                range: coverStart.upperBound..<source.endIndex
            )
        )
        let cover = String(source[coverStart.lowerBound..<coverEnd.lowerBound])
        let callback = try XCTUnwrap(cover.range(of: "onCaptured:"))
        let requestCheck = try XCTUnwrap(
            cover.range(
                of: "captureRequestID == requestID",
                range: callback.upperBound..<cover.endIndex
            ),
            "a late delegate callback must still belong to the currently presented capture request"
        )
        let publication = try XCTUnwrap(
            cover.range(of: "selectedImage = image", range: callback.upperBound..<cover.endIndex)
        )

        XCTAssertLessThan(requestCheck.lowerBound, publication.lowerBound)
        XCTAssertTrue(cover.contains("let requestID = captureRequestID"))
        XCTAssertTrue(cover.contains("captureRequestID = nil"))

        let bindingStart = try XCTUnwrap(
            source.range(of: "private var capturePresentation: Binding<ProgressCaptureIntent?>")
        )
        let helperStart = try XCTUnwrap(
            source.range(of: "private func revokeCapturePresentation()", range: bindingStart.upperBound..<source.endIndex)
        )
        let binding = String(source[bindingStart.lowerBound..<helperStart.lowerBound])
        XCTAssertTrue(binding.contains("if intent == nil"))
        XCTAssertTrue(binding.contains("revokeCapturePresentation()"))

        let helperEnd = try XCTUnwrap(
            source.range(of: "private var selectedPhotos", range: helperStart.upperBound..<source.endIndex)
        )
        let helper = String(source[helperStart.lowerBound..<helperEnd.lowerBound])
        XCTAssertTrue(helper.contains("captureIntent = nil"))
        XCTAssertTrue(helper.contains("captureOperation = nil"))
        XCTAssertTrue(helper.contains("captureRequestID = nil"))

        let boundaryStart = try XCTUnwrap(source.range(of: ".onChange(of: session.profile?.userID)"))
        let boundaryEnd = try XCTUnwrap(
            source.range(of: ".apexPopover", range: boundaryStart.upperBound..<source.endIndex)
        )
        let boundary = String(source[boundaryStart.lowerBound..<boundaryEnd.lowerBound])
        XCTAssertTrue(boundary.contains("captureRequestID = nil"))
    }

    func testProgressCameraCloseStopsTheCaptureLifecycleBeforeDismissing() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Avatar/ProgressCameraView.swift")
        )
        XCTAssertTrue(source.contains("Button(language.text(\"Close\"), action: closeCamera)"))

        let helperStart = try XCTUnwrap(source.range(of: "private func closeCamera()"))
        let helperEnd = try XCTUnwrap(
            source.range(of: "private var timerPicker", range: helperStart.upperBound..<source.endIndex)
        )
        let helper = String(source[helperStart.lowerBound..<helperEnd.lowerBound])
        let cancel = try XCTUnwrap(helper.range(of: "countdownTask?.cancel()"))
        let stop = try XCTUnwrap(helper.range(of: "controller.stop()"))
        let dismiss = try XCTUnwrap(helper.range(of: "onClose()"))

        XCTAssertLessThan(cancel.lowerBound, stop.lowerBound)
        XCTAssertLessThan(stop.lowerBound, dismiss.lowerBound)
    }
}
