/*
 * The progress camera, its ghost and the screens around it, laid out for real.
 *
 * The simulator has no camera, so these host the actual screens at iPhone
 * sizes with a stand-in for the permission prompt and the photo download,
 * then read back where each control landed.
 */
import SwiftUI
import XCTest
@testable import APEX

@MainActor
final class ProgressCameraTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
    }

    // MARK: - Laying a screen out

    private static let phones: [(name: String, size: CGSize)] = [
        ("iPhone SE", CGSize(width: 375, height: 667)),
        ("iPhone 16", CGSize(width: 393, height: 852)),
        ("iPhone 16 Pro Max", CGSize(width: 440, height: 956)),
    ]

    private final class Frames: @unchecked Sendable {
        var value: [String: CGRect] = [:]
    }

    private struct Layout {
        let frames: [String: CGRect]
        /// The part of the screen a control has to sit inside to be reachable.
        let safe: CGRect

        func assertReachable(
            _ names: [String], _ context: String,
            file: StaticString = #filePath, line: UInt = #line
        ) {
            for name in names {
                guard let frame = frames[name] else {
                    XCTFail("\(context): \(name) is not on the screen at all", file: file, line: line)
                    continue
                }
                XCTAssertTrue(
                    safe.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                    "\(context): \(name) at \(frame.integral) leaves the screen \(safe.integral)",
                    file: file, line: line
                )
            }
        }
    }

    /// Lays the view out in a window of the given size and waits until every
    /// name in `expecting` has reported where it is.
    private func layOut(
        _ view: some View,
        size: CGSize,
        expecting: [String] = [],
        named name: String
    ) async throws -> Layout {
        let frames = Frames()
        let host = UIHostingController(
            rootView: view.onPreferenceChange(ProgressLayoutFrames.self) { frames.value = $0 }
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        window?.isHidden = true
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        host.view.layoutIfNeeded()
        for _ in 0..<60 where !expecting.allSatisfy({ frames.value[$0] != nil }) || frames.value.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        /* One more turn, so a photo that has just arrived has been laid out. */
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        keepPicture(of: window, named: name)
        return Layout(frames: frames.value, safe: host.view.bounds.inset(by: host.view.safeAreaInsets))
    }

    /// A layout is a visual thing. Run with TEST_RUNNER_APEX_LAYOUT_SHOTS set
    /// to a folder and every screen checked here is also kept as a picture.
    private func keepPicture(of window: UIWindow, named name: String) {
        guard let folder = ProcessInfo.processInfo.environment["APEX_LAYOUT_SHOTS"] else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let directory = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: directory.appending(path: name.replacingOccurrences(of: ":", with: "-") + ".png"))
    }

    private func photo(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static let ghosts: [(name: String, size: CGSize)] = [
        ("iPhone camera photo, 3:4", CGSize(width: 1800, height: 2400)),
        ("screen-shaped photo", CGSize(width: 900, height: 1950)),
        ("square library photo", CGSize(width: 1600, height: 1600)),
        ("landscape library photo, 4:3", CGSize(width: 2400, height: 1800)),
    ]

    private func row(
        owner: UUID, pose: String = "front", date: String = "2026-10-01",
        key: String = "ios-progress-1", aspectRatio: Double = 0.75
    ) -> ProgressPhoto {
        let id = UUID()
        return ProgressPhoto(
            id: id, userID: owner, localDate: date, capturedAt: "\(date)T07:00:00Z", pose: pose,
            storagePath: "\(owner)/\(id)-original.jpg", thumbnailPath: "\(owner)/\(id)-thumb.jpg",
            width: 1800, height: 2400, aspectRatio: aspectRatio,
            cropX: 0.5, cropY: 0.5, cropScale: 1,
            referencePhotoID: nil, weightKG: nil, note: "", clientIdempotencyKey: key
        )
    }

    // MARK: - The comparison and the review

    /// C10. Two photos of different shapes share one pair of panels. Each
    /// label has to stay inside its own panel, whichever photo is wider.
    func testComparisonLabelsStayInsideTheirPanelsWhenThePhotosDifferInShape() async throws {
        let shapes = Self.ghosts
        for phone in Self.phones {
            for (first, second) in [(shapes[0], shapes[1]), (shapes[1], shapes[0]), (shapes[0], shapes[2]), (shapes[3], shapes[0])] {
                let session = AppSession(developerSandboxRole: .coach)
                let owner = try XCTUnwrap(session.accountOperationLease()).ownerID
                let before = row(owner: owner, date: "2026-08-01", aspectRatio: first.size.width / first.size.height)
                let after = row(owner: owner, date: "2026-10-01", aspectRatio: second.size.width / second.size.height)
                let images = [before.id: photo(first.size), after.id: photo(second.size)]
                let view = ProgressComparisonView(
                    before: before, after: after, onClose: {},
                    loadImage: { try XCTUnwrap(images[$0.id]) }
                )
                .environment(session)
                let names = ["close", "beforePanel", "afterPanel", "beforeLabel", "afterLabel"]
                let context = "\(phone.name), before is a \(first.name), after is a \(second.name)"
                let layout = try await layOut(view, size: phone.size, expecting: names, named: "comparison, \(context)")
                layout.assertReachable(["close", "beforePanel", "afterPanel"], context)
                for side in ["before", "after"] {
                    let panel = try XCTUnwrap(layout.frames["\(side)Panel"], context)
                    let label = try XCTUnwrap(layout.frames["\(side)Label"], context)
                    XCTAssertTrue(
                        panel.insetBy(dx: -0.5, dy: -0.5).contains(label),
                        "\(context): the \(side) label at \(label.integral) is cut off by its panel \(panel.integral)"
                    )
                }
            }
        }
    }

    /// C10. The review page shows the new photo above Retake and Save. A
    /// square or landscape photo must not widen the page and hide them.
    func testReviewingAPhotoOfAnyShapeKeepsRetakeAndSaveOnScreen() async throws {
        for phone in Self.phones {
            for shape in Self.ghosts {
                let session = AppSession(developerSandboxRole: .coach)
                let view = VisualProgressView(reviewing: photo(shape.size)).environment(session)
                let context = "\(phone.name), reviewing a \(shape.name)"
                let layout = try await layOut(
                    view, size: phone.size, expecting: ["reviewCard", "retake", "save"], named: context
                )
                for name in ["reviewCard", "retake", "save"] {
                    let frame = try XCTUnwrap(layout.frames[name], "\(context): \(name) is missing")
                    XCTAssertTrue(
                        frame.minX >= layout.safe.minX - 0.5 && frame.maxX <= layout.safe.maxX + 0.5,
                        "\(context): \(name) spans x \(Int(frame.minX))...\(Int(frame.maxX)) on a screen \(Int(layout.safe.width)) wide"
                    )
                }
            }
        }
    }

    // MARK: - The camera

    private static let cameraControls = ["close", "pose", "framing", "timerRow", "library", "shutter"]

    private func camera(
        ghost: UIImage?,
        framing: ProgressPhotoEngine.FramingMode = .full,
        frontCameraAllowed: Bool = false,
        cameraAllowed: Bool = true
    ) throws -> some View {
        let session = AppSession(developerSandboxRole: .coach)
        let operation = try XCTUnwrap(session.accountOperationLease())
        session.data.settings?.addons["allow_front_camera_scanning"] = .bool(frontCameraAllowed)
        let previous = row(owner: operation.ownerID)
        session.data.progressPhotos = ghost == nil ? [] : [previous]
        var intent = ProgressCaptureIntent()
        intent.framing = framing
        return ProgressCameraView(
            intent: intent,
            reference: ghost == nil ? nil : previous,
            operation: operation,
            controller: ProgressCameraController(accessAnswer: { cameraAllowed }),
            loadReferenceImage: { _ in ghost },
            onClose: {},
            onCaptured: { _, _ in }
        )
        .environment(session)
    }

    /// C1. The previous photo is drawn under the live preview. It must never
    /// decide how wide the screen is.
    func testTheGhostNeverPushesTheCameraControlsOffScreen() async throws {
        for phone in Self.phones {
            let bare = try await layOut(
                try camera(ghost: nil), size: phone.size, expecting: Self.cameraControls,
                named: "camera, \(phone.name), first photo"
            )
            bare.assertReachable(Self.cameraControls, "\(phone.name), first photo")

            for ghost in Self.ghosts {
                let context = "\(phone.name), ghost is a \(ghost.name)"
                let layout = try await layOut(
                    try camera(ghost: photo(ghost.size)), size: phone.size,
                    expecting: Self.cameraControls + ["ghostSlider"], named: "camera, \(context)"
                )
                layout.assertReachable(Self.cameraControls + ["ghostSlider"], context)
                /* The timer row gains the Ghost slider, so only the controls
                   above it are expected to stay exactly where they were. */
                for name in ["close", "pose", "framing"] {
                    let moved = try XCTUnwrap(layout.frames[name]), still = try XCTUnwrap(bare.frames[name])
                    XCTAssertEqual(moved.minX, still.minX, accuracy: 1, "\(context): the ghost moved \(name)")
                    XCTAssertEqual(moved.minY, still.minY, accuracy: 1, "\(context): the ghost moved \(name)")
                    XCTAssertEqual(moved.width, still.width, accuracy: 1, "\(context): the ghost resized \(name)")
                }
            }
        }
    }

    /// C2. The shutter row belongs at the bottom of the screen, clear of the
    /// outline, whether or not the front-camera setting is on, and the pose
    /// hint must not sit on top of the timer.
    func testTheShutterSitsBelowTheOutlineWhateverTheFrontCameraSetting() async throws {
        let names = Self.cameraControls + ["guide", "hint"]
        for phone in Self.phones {
            for framing in [ProgressPhotoEngine.FramingMode.full, .torso] {
                var shutters: [CGRect] = []
                for allowed in [false, true] {
                    let context = "\(phone.name), \(framing.rawValue), front camera setting \(allowed ? "on" : "off")"
                    let layout = try await layOut(
                        try camera(ghost: nil, framing: framing, frontCameraAllowed: allowed),
                        size: phone.size, expecting: names, named: "camera, \(context)"
                    )
                    layout.assertReachable(Self.cameraControls, context)
                    let shutter = try XCTUnwrap(layout.frames["shutter"], context)
                    let guide = try XCTUnwrap(layout.frames["guide"], context)
                    let hint = try XCTUnwrap(layout.frames["hint"], context)
                    let timer = try XCTUnwrap(layout.frames["timerRow"], context)
                    let library = try XCTUnwrap(layout.frames["library"], context)
                    XCTAssertEqual(
                        shutter.maxY, layout.safe.maxY - 16, accuracy: 1,
                        "\(context): the shutter is not at the bottom of the screen"
                    )
                    for (name, control) in [("shutter", shutter), ("Library", library), ("timer", timer)] {
                        XCTAssertFalse(
                            guide.intersects(control),
                            "\(context): \(name) at \(control.integral) sits over the outline \(guide.integral)"
                        )
                    }
                    XCTAssertFalse(
                        hint.intersects(timer),
                        "\(context): the pose hint \(hint.integral) overlaps the timer \(timer.integral)"
                    )
                    shutters.append(shutter)
                }
                XCTAssertEqual(
                    shutters[0].integral, shutters[1].integral,
                    "\(phone.name), \(framing.rawValue): the setting moves the shutter"
                )
            }
        }
    }

    /// With a previous photo loaded the timer row gains the Ghost slider. The
    /// word must stay readable and the row must stay one line tall, or the
    /// slider swells over the pose hint.
    func testTheGhostSliderKeepsItsLabelAndLeavesThePoseHintClear() async throws {
        for phone in Self.phones {
            let context = "\(phone.name), with a previous photo"
            let layout = try await layOut(
                try camera(ghost: photo(Self.ghosts[0].size)), size: phone.size,
                expecting: Self.cameraControls + ["ghostSlider", "ghostLabel", "hint"],
                named: "camera, \(context), slider row"
            )
            layout.assertReachable(Self.cameraControls + ["ghostSlider", "ghostLabel"], context)
            let label = try XCTUnwrap(layout.frames["ghostLabel"], context)
            let slider = try XCTUnwrap(layout.frames["ghostSlider"], context)
            let timer = try XCTUnwrap(layout.frames["timerRow"], context)
            let hint = try XCTUnwrap(layout.frames["hint"], context)
            XCTAssertGreaterThan(label.width, 30, "\(context): the word Ghost is squeezed to \(label.width) points")
            XCTAssertLessThan(label.height, 20, "\(context): the word Ghost wraps onto \(label.height) points of lines")
            XCTAssertLessThan(slider.height, 50, "\(context): the slider capsule is \(slider.height) points tall")
            XCTAssertFalse(
                hint.intersects(timer),
                "\(context): the timer row \(timer.integral) covers the pose hint \(hint.integral)"
            )
        }
    }

    /// C3. Refusing the camera used to leave a black screen and a dead
    /// shutter. The screen now says what happened and offers the way to fix it.
    func testARefusedCameraExplainsItselfAndOffersSettings() async throws {
        let refused = ProgressCameraController(accessAnswer: { false })
        await refused.start(position: .back)
        XCTAssertTrue(refused.accessDenied)
        XCTAssertFalse(refused.isReady)

        let allowed = ProgressCameraController(accessAnswer: { true })
        await allowed.start(position: .back)
        XCTAssertFalse(allowed.accessDenied)
        allowed.stop()

        for phone in Self.phones {
            let context = "\(phone.name), camera refused"
            let layout = try await layOut(
                try camera(ghost: nil, cameraAllowed: false), size: phone.size,
                expecting: ["close", "library", "cameraDenied", "openSettings"], named: "camera, \(context)"
            )
            layout.assertReachable(["close", "library", "cameraDenied", "openSettings"], context)

            let normal = try await layOut(
                try camera(ghost: nil), size: phone.size, expecting: Self.cameraControls,
                named: "camera, \(phone.name), camera allowed"
            )
            XCTAssertNil(normal.frames["cameraDenied"], "\(phone.name): the notice shows although the camera is allowed")
        }
    }
}
