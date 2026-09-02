/*
 * Golden parity for ProgressPhotoEngine and ProgressComparison against
 * src/lib/progressPhoto.ts and src/lib/progressComparison.ts.
 */
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
