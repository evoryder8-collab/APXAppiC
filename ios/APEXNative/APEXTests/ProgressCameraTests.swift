/*
 * The progress camera, its ghost and the screens around it, laid out for real.
 *
 * The simulator has no camera, so these host the actual screens at iPhone
 * sizes with a stand-in for the permission prompt and the photo download,
 * then read back where each control landed.
 */
import AVFoundation
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

    /// Puts the view on screen in a window of the given size. The frames keep
    /// following it for as long as it is shown.
    private func show(_ view: some View, size: CGSize) throws -> (frames: Frames, host: UIViewController) {
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
        return (frames, host)
    }

    /// Lays the view out in a window of the given size and waits until every
    /// name in `expecting` has reported where it is.
    private func layOut(
        _ view: some View,
        size: CGSize,
        expecting: [String] = [],
        named name: String
    ) async throws -> Layout {
        let (frames, host) = try show(view, size: size)
        let window = try XCTUnwrap(self.window)
        for _ in 0..<60 where !expecting.allSatisfy({ frames.value[$0] != nil }) || frames.value.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        /* One more turn, so a photo that has just arrived has been laid out. */
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        keepPicture(of: window, named: name)
        return Layout(frames: frames.value, safe: host.view.bounds.inset(by: host.view.safeAreaInsets))
    }

    private func picture(of window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// A layout is a visual thing. Run with TEST_RUNNER_APEX_LAYOUT_SHOTS set
    /// to a folder and every screen checked here is also kept as a picture.
    private func keepPicture(of window: UIWindow, named name: String) {
        guard let folder = ProcessInfo.processInfo.environment["APEX_LAYOUT_SHOTS"] else { return }
        let image = picture(of: window)
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

    /// A portrait photo that is red on its left half and blue on its right,
    /// stored the way a camera stores it: sideways, with an orientation flag.
    private func sidedPhoto() throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sensor = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            /* Rotated a quarter turn clockwise for display, the top half of
               the sensor frame becomes the right half of the photo. */
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 150))
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 150, width: 400, height: 150))
        }
        return UIImage(cgImage: try XCTUnwrap(sensor.cgImage), scale: 1, orientation: .right)
    }

    /// Red, green and blue of one point of an image as it is displayed.
    private func colour(of image: UIImage, at unit: CGPoint) throws -> (red: Int, green: Int, blue: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        UIGraphicsPushContext(context)
        /* Flipped to UIKit's top-left origin, then moved so the wanted point
           lands on the single pixel. */
        context.translateBy(x: 0, y: 1)
        context.scaleBy(x: 1, y: -1)
        image.draw(at: CGPoint(x: -unit.x * image.size.width, y: -unit.y * image.size.height))
        UIGraphicsPopContext()
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
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

    /// The sensor's whole frame with a white band across its middle, or the
    /// rows of it that a photo keeps.
    private func banded(rows: Range<Int>) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 600, height: rows.count)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 300 - rows.lowerBound, width: 600, height: 200))
        }
    }

    /// How tall the white band is, in points, down the middle of a panel.
    private func bandHeight(in screen: UIImage, panel: CGRect) throws -> CGFloat {
        let cg = try XCTUnwrap(screen.cgImage)
        let scale = CGFloat(cg.width) / screen.size.width
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let column = Int(panel.midX * scale)
        /* The middle half of the panel, clear of the label at its top. */
        let rows = Int((panel.minY + panel.height * 0.25) * scale)..<Int((panel.minY + panel.height * 0.75) * scale)
        let bright = rows.filter { row in
            let offset = (row * cg.width + column) * 4
            return Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2]) > 384
        }
        return CGFloat(bright.count) / scale
    }

    /// A torso photo taken before the camera cut its pictures is the sensor's
    /// whole frame. One taken since keeps the full width and gives up some
    /// height. Each filled into a panel, the newer came out 6.7 percent
    /// larger, so the same person was a different size on each side.
    func testTorsoPhotosFromBeforeAndAfterTheCutShowTheSamePersonAtTheSameSize() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        let owner = try XCTUnwrap(session.accountOperationLease()).ownerID
        let uncut = (0..<2).map {
            row(owner: owner, date: "2026-08-0\($0 + 1)", key: "framing:torso:uncut\($0)", aspectRatio: 0.75)
        }
        let cut = (0..<2).map {
            row(owner: owner, date: "2026-10-0\($0 + 1)", key: "framing:torso:cut\($0)", aspectRatio: 0.8)
        }
        var images: [UUID: UIImage] = [:]
        for photo in uncut { images[photo.id] = banded(rows: 0..<800) }
        for photo in cut { images[photo.id] = banded(rows: 25..<775) }
        func bands(_ before: ProgressPhoto, _ after: ProgressPhoto) async throws -> (before: CGFloat, after: CGFloat, panel: CGFloat) {
            let view = ProgressComparisonView(
                before: before, after: after, onClose: {},
                loadImage: { try XCTUnwrap(images[$0.id]) }
            )
            .environment(session)
            let layout = try await layOut(
                view, size: Self.phones[1].size, expecting: ["beforePanel", "afterPanel"],
                named: "comparison, torso \(before.aspectRatio) beside torso \(after.aspectRatio)"
            )
            let screen = picture(of: try XCTUnwrap(window))
            let left = try XCTUnwrap(layout.frames["beforePanel"]), right = try XCTUnwrap(layout.frames["afterPanel"])
            return (try bandHeight(in: screen, panel: left), try bandHeight(in: screen, panel: right), left.height)
        }

        for (before, after) in [(uncut[0], cut[0]), (cut[0], uncut[0])] {
            let shown = try await bands(before, after)
            XCTAssertEqual(shown.before, shown.after, accuracy: 1, "the same person is a different size on each side")
            XCTAssertEqual(
                shown.before, shown.panel * 200 / 800, accuracy: 1,
                "the pair is no longer at the size the whole frame fills the panel"
            )
        }
        let older = try await bands(uncut[0], uncut[1])
        XCTAssertEqual(older.before, older.panel * 200 / 800, accuracy: 1, "two photos from before the cut fill their panels as before")
        XCTAssertEqual(older.after, older.panel * 200 / 800, accuracy: 1, "two photos from before the cut fill their panels as before")
        let newer = try await bands(cut[0], cut[1])
        XCTAssertEqual(newer.before, newer.panel * 200 / 750, accuracy: 1, "two photos taken since the cut fill their panels as before")
        XCTAssertEqual(newer.after, newer.panel * 200 / 750, accuracy: 1, "two photos taken since the cut fill their panels as before")
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

    /// A controller that has been allowed the camera and has chosen its lens.
    /// The simulator takes seconds to give up on a camera it does not have,
    /// so this does not wait for the session itself.
    private func controller(on position: AVCaptureDevice.Position) async throws -> ProgressCameraController {
        let controller = ProgressCameraController(accessAnswer: { true })
        Task { await controller.start(position: position) }
        for _ in 0..<200 where controller.position != position {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(controller.position, position)
        return controller
    }

    private static let cameraControls = ["close", "pose", "framing", "timerRow", "library", "shutter"]

    private func camera(
        ghost: UIImage?,
        pose: String = "front",
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
        intent.pose = pose
        intent.framing = framing
        return ProgressCameraView(
            intent: intent,
            photos: session.data.progressPhotos,
            operation: operation,
            controller: ProgressCameraController(accessAnswer: { cameraAllowed }),
            loadReferenceImage: { _ in ghost },
            onClose: {},
            onCaptured: { _, _, _ in }
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

        let allowed = try await controller(on: .back)
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

    /// C4. The ghost is there to line a pose up with the same pose. A front
    /// photo under a side shot is worse than no ghost at all.
    func testTheCameraNeverGhostsAPhotoOfAnotherPose() async throws {
        let size = Self.phones[1].size
        let front = try await layOut(
            try camera(ghost: photo(Self.ghosts[0].size), pose: "front"), size: size,
            expecting: ["shutter", "ghostSlider"], named: "camera, front pose, front photo owned"
        )
        XCTAssertNotNil(front.frames["ghostSlider"], "the previous front photo should ghost a front shot")

        for pose in ["side", "back"] {
            let other = try await layOut(
                try camera(ghost: photo(Self.ghosts[0].size), pose: pose), size: size,
                expecting: ["shutter"], named: "camera, \(pose) pose, front photo owned"
            )
            XCTAssertNil(other.frames["ghostSlider"], "a front photo is ghosted under a \(pose) shot")
        }
    }

    /// C9. A saved photo keeps the person's true left and right whichever
    /// camera took it, so a selfie and a rear photo of one pose line up.
    func testAFrontCameraPhotoIsSavedWithTheSameLeftAndRightAsARearOne() async throws {
        let shot = try sidedPhoto()
        XCTAssertGreaterThan(try colour(of: shot, at: CGPoint(x: 0.25, y: 0.5)).red, 200, "the fixture is red on the left")
        XCTAssertGreaterThan(try colour(of: shot, at: CGPoint(x: 0.75, y: 0.5)).blue, 200, "and blue on the right")

        for (name, position) in [("front", AVCaptureDevice.Position.front), ("rear", .back)] {
            let controller = try await controller(on: position)
            var saved: UIImage?
            controller.capture { saved = $0 }
            controller.finishCapture(with: shot)
            controller.stop()

            let image = try XCTUnwrap(saved, "the \(name) camera handed nothing on")
            XCTAssertEqual(image.size, shot.size, "the \(name) camera photo is no longer upright")
            let left = try colour(of: image, at: CGPoint(x: 0.25, y: 0.5))
            let right = try colour(of: image, at: CGPoint(x: 0.75, y: 0.5))
            XCTAssertGreaterThan(left.red, 200, "the \(name) camera saved the photo mirrored")
            XCTAssertGreaterThan(right.blue, 200, "the \(name) camera saved the photo mirrored")
        }
    }

    /// C9. The live selfie preview is a mirror, so under it the ghost is
    /// mirrored too. Under the rear camera it is shown as it was saved.
    func testTheGhostIsMirroredOnlyUnderTheMirroredSelfiePreview() async throws {
        let size = Self.phones[1].size
        for (name, front) in [("rear", false), ("front", true)] {
            _ = try await layOut(
                try camera(ghost: try sidedPhoto(), frontCameraAllowed: front), size: size,
                expecting: ["shutter", "ghostSlider"], named: "camera, sided ghost under the \(name) camera"
            )
            let screen = picture(of: try XCTUnwrap(window))
            /* Beside the outline, where nothing else is drawn. */
            let left = try colour(of: screen, at: CGPoint(x: 0.06, y: 0.45))
            let right = try colour(of: screen, at: CGPoint(x: 0.94, y: 0.45))
            if front {
                XCTAssertGreaterThan(left.blue, left.red + 20, "under the selfie preview the ghost is not mirrored")
                XCTAssertGreaterThan(right.red, right.blue + 20, "under the selfie preview the ghost is not mirrored")
            } else {
                XCTAssertGreaterThan(left.red, left.blue + 20, "under the rear camera the ghost is flipped")
                XCTAssertGreaterThan(right.blue, right.red + 20, "under the rear camera the ghost is flipped")
            }
        }
    }

    /// C12. The label beside the shutter names the camera in use.
    func testTheCameraLabelNamesTheCameraInUse() async throws {
        let front = try await controller(on: .front)
        XCTAssertEqual(front.lensName, "FRONT")
        front.stop()
        let rear = try await controller(on: .back)
        XCTAssertEqual(rear.lensName, "REAR")
        rear.flip()
        XCTAssertEqual(rear.lensName, "FRONT", "flipping changes the label with the camera")
        rear.stop()
    }

    /// C12. A capture that produces no photo used to end in silence, with the
    /// shutter live again and nothing saved. It now answers, with nothing.
    func testAFailedCaptureAnswersInsteadOfEndingSilently() async throws {
        /* The simulator has no camera, so every capture here is a failed one. */
        let controller = ProgressCameraController(accessAnswer: { true })
        var answers: [UIImage?] = []
        controller.capture { answers.append($0) }
        for _ in 0..<100 where answers.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(answers.count, 1, "the capture never reported back")
        XCTAssertNil(answers.first ?? nil)
        controller.stop()

        var direct: [UIImage?] = []
        controller.capture { direct.append($0) }
        controller.finishCapture(with: nil)
        XCTAssertEqual(direct.count, 1, "a photo that could not be read was dropped without a word")
        controller.stop()
    }

    /// A 3:4 sensor frame, green with a magenta band down each side edge.
    private func sensorFrame(sideways: Bool) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800), format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 800))
            context.fill(CGRect(x: 540, y: 0, width: 60, height: 800))
        }
        guard sideways else { return upright }
        /* The way the camera delivers it: sensor rows, turned for display. */
        let turned = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).image { context in
            context.cgContext.translateBy(x: 0, y: 600)
            context.cgContext.rotate(by: -.pi / 2)
            upright.draw(at: .zero)
        }
        return UIImage(cgImage: try XCTUnwrap(turned.cgImage), scale: 1, orientation: .right)
    }

    /// C5. The saved picture is the one that was framed. The preview shows the
    /// middle of a wider sensor frame, and the save used to keep all of it.
    func testACaptureIsCutToThePictureThatWasFramed() throws {
        let preview = 393.0 / 852.0
        for sideways in [false, true] {
            let frame = try sensorFrame(sideways: sideways)
            XCTAssertEqual(frame.size, CGSize(width: 600, height: 800))
            XCTAssertGreaterThan(try colour(of: frame, at: CGPoint(x: 0.02, y: 0.5)).red, 200, "fixture edge is magenta")

            for framing in [ProgressPhotoEngine.FramingMode.full, .free] {
                let saved = frame.progressCapture(framing: framing, previewAspectRatio: preview)
                XCTAssertEqual(saved.size.height, 800, accuracy: 1, framing.rawValue)
                XCTAssertEqual(saved.size.width / saved.size.height, preview, accuracy: 0.005, framing.rawValue)
                for x in [0.01, 0.5, 0.99] {
                    let pixel = try colour(of: saved, at: CGPoint(x: x, y: 0.5))
                    XCTAssertTrue(
                        pixel.green > 200 && pixel.red < 60,
                        "\(framing.rawValue): the part of the frame the preview never showed was saved (x \(x): \(pixel))"
                    )
                }
            }

            let torso = frame.progressCapture(framing: .torso, previewAspectRatio: preview)
            XCTAssertEqual(torso.size.width, 600, accuracy: 1)
            XCTAssertEqual(torso.size.width / torso.size.height, 0.8, accuracy: 0.005)
            XCTAssertGreaterThan(
                try colour(of: torso, at: CGPoint(x: 0.02, y: 0.5)).red, 200,
                "a torso photo keeps the full width, for room around the arms"
            )
        }
    }

    /// C5. The crop is measured against the live preview, which is the whole
    /// screen and not just the area inside the safe margins.
    func testThePreviewTheCropIsMeasuredAgainstFillsTheScreen() async throws {
        for phone in Self.phones {
            let layout = try await layOut(
                try camera(ghost: nil), size: phone.size, expecting: ["preview", "shutter"],
                named: "camera, \(phone.name), preview"
            )
            XCTAssertEqual(layout.frames["preview"], CGRect(origin: .zero, size: phone.size), phone.name)
        }
    }

    /// C8. Opening the page must not build the whole timeline, or the request
    /// for older photos at its end would fire at once and every page would
    /// load in a chain. Only the rows near the screen exist until it scrolls.
    func testOpeningTheTimelineBuildsOnlyTheRowsNearTheScreen() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        let owner = try XCTUnwrap(session.accountOperationLease()).ownerID
        session.data.progressPhotos = (0..<130).map { index in
            row(owner: owner, date: String(format: "2026-%02d-%02d", 1 + index / 28, 1 + index % 28))
        }
        let layout = try await layOut(
            VisualProgressView().environment(session), size: Self.phones[1].size,
            expecting: [], named: "timeline of 130 photos"
        )
        let built = layout.frames.keys.filter { $0.hasPrefix("timelineRow") }.count
        XCTAssertGreaterThan(built, 0, "the timeline shows no photos at all")
        XCTAssertLessThan(built, 40, "\(built) of 130 rows were built on open, so the end of the list is reached at once")
    }

    // MARK: - The timeline beyond its first page

    /// Day `number` of a calendar of 28-day months, later numbers later.
    private static func day(_ number: Int) -> String {
        String(format: "2025-%02d-%02d", 1 + number / 28, 1 + number % 28)
    }

    /// The timeline in a window tall enough for every row and the end of the
    /// list to be on screen, so older photos load without anything scrolling.
    private func timeline(of session: AppSession, older: OlderPhotos, ticked: [UUID] = []) throws -> Frames {
        let view = VisualProgressView(ticked: ticked) { earlier in
            await older.page(below: session.data.progressPhotos, after: earlier)
        }
        /* The screen reports its own frame too, so every new width is a
           fresh report of everything on it. */
        return try show(
            view.environment(session).layoutFrame("screen"), size: CGSize(width: 393, height: 20_000)
        ).frames
    }

    private func shows(_ photo: ProgressPhoto, in frames: Frames) -> Bool {
        frames.value["timelineRow \(photo.id)"] != nil
    }

    /// Gives the screen a few seconds to get there, and fails if it does not.
    private func wait(
        for what: String, file: StaticString = #filePath, line: UInt = #line, _ reached: () -> Bool
    ) async throws {
        let width = window?.frame.width ?? 0
        for turn in 0..<80 where !reached() {
            try await Task.sleep(for: .milliseconds(50))
            /* A row removed while the screen was already updating stays in
               the last report until the frames next change, so the window
               is given a new width. */
            window?.frame.size.width = width + CGFloat(turn % 2)
            window?.rootViewController?.view.layoutIfNeeded()
        }
        window?.frame.size.width = width
        XCTAssertTrue(reached(), what, file: file, line: line)
    }

    /// A page of older photos answers one question: what comes after the
    /// photos that were loaded when it was asked. If the first page ends
    /// somewhere else by the time it arrives, it no longer joins on. Joined
    /// on regardless, it left a hole in the timeline, so it is asked again.
    func testAPageAskedBeforeTheFirstPageMovedIsAskedAgain() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        let owner = try XCTUnwrap(session.accountOperationLease()).ownerID
        let firstPage = (0..<120).map { row(owner: owner, date: Self.day(200 - $0)) }
        let baseline = row(owner: owner, date: Self.day(10))
        session.data.progressPhotos = firstPage
        let older = OlderPhotos(firstPage + [baseline])
        older.hold()
        let frames = try timeline(of: session, older: older)
        try await wait(for: "the end of the timeline asks for older photos") { older.asked > 0 }

        /* Two photos saved on another device push the last two off the first
           page while the answer is on its way. */
        let saved = [row(owner: owner, date: Self.day(202)), row(owner: owner, date: Self.day(201))]
        older.all += saved
        session.data.progressPhotos = saved + firstPage.dropLast(2)
        try await wait(for: "the new photos are on the timeline") { shows(saved[0], in: frames) }
        older.release()

        try await wait(for: "the photos that left the first page are still on the timeline") {
            firstPage.suffix(2).allSatisfy { shows($0, in: frames) } && shows(baseline, in: frames)
        }
    }

    /// An old photo imported from the library is filed under its own date,
    /// below the first page. The refresh that follows a save brings the newest
    /// 120 again, and the import then has to be found among the older photos.
    /// It used to be in neither, gone until the screen was opened again.
    func testAnImportedOldPhotoIsStillOnTheTimelineAfterTheRefreshThatFollowsItsSave() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        let owner = try XCTUnwrap(session.accountOperationLease()).ownerID
        let firstPage = (0..<120).map { row(owner: owner, date: Self.day(200 - $0)) }
        let earlier = (0..<3).map { row(owner: owner, date: Self.day(10 - $0)) }
        session.data.progressPhotos = firstPage
        let older = OlderPhotos(firstPage + earlier)
        let frames = try timeline(of: session, older: older)
        try await wait(for: "the older photos load") { earlier.allSatisfy { shows($0, in: frames) } }

        /* Saving uploads the photo, then adds it to the photos in memory. */
        let imported = row(owner: owner, date: Self.day(2))
        older.all.append(imported)
        session.data.progressPhotos.insert(imported, at: 0)
        try await wait(for: "the imported photo is on the timeline") { shows(imported, in: frames) }

        /* The refresh: the first page is the newest 120 again. */
        let asked = older.asked
        older.hold()
        session.data.progressPhotos = firstPage
        try await wait(for: "the older photos are asked for again once a photo has left the first page") {
            older.asked > asked
        }
        older.release()
        try await wait(for: "the imported photo is on the timeline, among the older photos") {
            older.asked > asked && shows(imported, in: frames) && earlier.allSatisfy { shows($0, in: frames) }
        }
    }

    /// Older photos are loaded by this screen and kept by it. They belong to
    /// the account they were loaded for, and leave the timeline when it does.
    func testOlderPhotosLeaveWithTheAccountTheyWereLoadedFor() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        let owner = try XCTUnwrap(session.accountOperationLease()).ownerID
        let firstPage = (0..<120).map { row(owner: owner, date: Self.day(200 - $0)) }
        let earlier = (0..<3).map { row(owner: owner, date: Self.day(10 - $0)) }
        session.data.progressPhotos = firstPage
        let older = OlderPhotos(firstPage + earlier)
        let frames = try timeline(of: session, older: older)
        try await wait(for: "the older photos load") { earlier.allSatisfy { shows($0, in: frames) } }

        /* The next account's first page ends on the same day, so only the
           change of account says the older photos are not its own. */
        let next = AppSession(developerSandboxRole: .invitedClient)
        let nextOwner = try XCTUnwrap(next.accountOperationLease()).ownerID
        XCTAssertNotEqual(nextOwner, owner)
        let nextPage = (0..<120).map { row(owner: nextOwner, date: Self.day(200 - $0)) }
        var data = next.data
        data.progressPhotos = nextPage
        older.all = nextPage
        session.data = data
        try await wait(for: "the next account's photos are on the timeline") { shows(nextPage[0], in: frames) }
        try await wait(for: "the older photos of the account that left are off the timeline") {
            !earlier.contains { shows($0, in: frames) }
        }
    }

    /// A comparison needs both of its photos on the timeline. An older photo
    /// that is ticked leaves with the older pages when they reload: its tick
    /// goes with it, and Compare is never offered for a photo that is not there.
    func testCompareIsOnlyOfferedForTwoPhotosOnTheTimeline() async throws {
        let session = AppSession(developerSandboxRole: .coach)
        let owner = try XCTUnwrap(session.accountOperationLease()).ownerID
        /* One photo a day, so the next one saved moves where the first page ends. */
        let firstPage = (0..<120).map { row(owner: owner, date: Self.day(200 - $0)) }
        let baseline = row(owner: owner, date: Self.day(10))
        session.data.progressPhotos = firstPage
        let older = OlderPhotos(firstPage + [baseline])
        let frames = try timeline(of: session, older: older, ticked: [baseline.id, firstPage[0].id])
        try await wait(for: "both ticked photos are on the timeline, so Compare is offered") {
            shows(baseline, in: frames) && frames.value["compare"] != nil
        }

        older.hold()
        let saved = row(owner: owner, date: Self.day(201))
        older.all.append(saved)
        session.data.progressPhotos.insert(saved, at: 0)
        try await wait(for: "the older photos give way when the first page ends somewhere else") {
            !shows(baseline, in: frames)
        }
        try await wait(for: "Compare is not offered while one of its photos is off the timeline") {
            frames.value["compare"] == nil
        }

        older.release()
        try await wait(for: "the older photos load again") { shows(baseline, in: frames) }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(frames.value["compare"], "a tick on a photo that left the timeline came back with it")
    }
}

/// Stands in for the server's older photos. It answers the question the app's
/// own paging asks, and can be made to take its time over it.
@MainActor
private final class OlderPhotos {
    var all: [ProgressPhoto]
    /// How many pages have been asked for.
    private(set) var asked = 0
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ all: [ProgressPhoto]) {
        self.all = all
    }

    func page(
        below firstPage: [ProgressPhoto], after earlier: [ProgressPhoto]
    ) async -> (photos: [ProgressPhoto], reachedEnd: Bool) {
        await ProgressPhotoEngine.earlierPage(firstPage: firstPage, earlier: earlier) { @Sendable day, limit in
            await self.rows(onOrBefore: day, limit: limit)
        }
    }

    private func rows(onOrBefore day: String, limit: Int) async -> [ProgressPhoto] {
        asked += 1
        if held {
            await withCheckedContinuation { waiting.append($0) }
        }
        return Array(
            all.filter { $0.localDate <= day }
                .sorted { ($0.localDate, $0.id.uuidString) > ($1.localDate, $1.id.uuidString) }
                .prefix(limit)
        )
    }

    func hold() {
        held = true
    }

    func release() {
        held = false
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
