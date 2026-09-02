import AVFoundation
import SwiftUI
import UIKit

/*
 * The progress camera, matching the web's ProgressCamera.
 *
 * The stock system picker cannot do the one thing this feature needs: show
 * the previous photo underneath the live preview so the next one can be
 * aligned to it. That ghost, the pose guides and the self-timer are the whole
 * reason two photos taken weeks apart are comparable at all.
 *
 * The microphone is never configured, and the session is torn down on the way
 * out, so the camera runs only while this screen is on screen.
 */
@MainActor
@Observable
final class ProgressCameraController: NSObject {
    /* AVCaptureSession is not Sendable, and starting it blocks. It is driven
       from one serial queue, which is the arrangement AVFoundation expects,
       and never touched concurrently from anywhere else. */
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated private let sessionQueue = DispatchQueue(label: "ch.apexperformance.progress-camera")
    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let depthOutput = AVCaptureDepthDataOutput()
    nonisolated(unsafe) private var synchronizer: AVCaptureDataOutputSynchronizer?
    nonisolated(unsafe) private var input: AVCaptureDeviceInput?
    nonisolated private let analyzer = ProgressFrameAnalyzer()
    private(set) var position: AVCaptureDevice.Position = .front
    private(set) var isReady = false
    /// Live distance and subject reading, when the device can measure it.
    let reading = ProgressDepthAnalyzer()
    private var captured: ((UIImage) -> Void)?
    private var lifecycleGeneration: UInt64 = 0

    func start(position: AVCaptureDevice.Position = .front) async {
        lifecycleGeneration &+= 1
        let requestGeneration = lifecycleGeneration
        isReady = false
        guard await AVCaptureDevice.requestAccess(for: .video),
              Task.isCancelled == false,
              lifecycleGeneration == requestGeneration else { return }
        self.position = position
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                configureOnQueue(position: position)
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        guard Task.isCancelled == false,
              lifecycleGeneration == requestGeneration else { return }
        isReady = true
    }

    func stop() {
        lifecycleGeneration &+= 1
        isReady = false
        captured = nil
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func flip() {
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        position = next
        sessionQueue.async { [self] in configureOnQueue(position: next) }
    }

    nonisolated private func configureOnQueue(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        /* Video only. The microphone is never requested, which is what lets
           the screen promise camera only, microphone off. */
        /* Prefer a camera that can measure depth: LiDAR on the back of a Pro
           device, TrueDepth on the front. A plain wide-angle still works, it
           simply reports no distance rather than a made-up one. */
        let preferred: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInLiDARDepthCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferred, mediaType: .video, position: position
        )
        guard let device = discovery.devices.first,
              let next = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(next) {
            session.addInput(next)
            input = next
        }
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            session.addOutput(videoOutput)
        }
        if !session.outputs.contains(depthOutput), session.canAddOutput(depthOutput) {
            depthOutput.isFilteringEnabled = true
            session.addOutput(depthOutput)
        }
        configureAnalysis()
    }

    nonisolated private func configureAnalysis() {
        let depthConnected = depthOutput.connection(with: .depthData)?.isEnabled ?? false
        let outputs: [AVCaptureOutput] = depthConnected ? [videoOutput, depthOutput] : [videoOutput]
        let sync = AVCaptureDataOutputSynchronizer(dataOutputs: outputs)
        sync.setDelegate(self, queue: sessionQueue)
        synchronizer = sync
        analyzer.onReading = { [weak self] distance, subject, hasDepth in
            Task { @MainActor [weak self] in
                self?.reading.update(distance: distance, subject: subject, hasDepth: hasDepth)
            }
        }
    }

    func capture(_ completion: @escaping (UIImage) -> Void) {
        captured = completion
        sessionQueue.async { [self] in
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
}

extension ProgressCameraController: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput collection: AVCaptureSynchronizedDataCollection
    ) {
        guard let video = collection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !video.sampleBufferWasDropped,
              let buffer = CMSampleBufferGetImageBuffer(video.sampleBuffer) else { return }
        let depth = (collection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData)
            .flatMap { $0.depthDataWasDropped ? nil : $0.depthData }
        analyzer.analyze(pixelBuffer: buffer, depth: depth)
    }
}

extension ProgressCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            /* A front-camera frame arrives mirrored relative to what the
               person saw, so it is flipped back to the image they aligned. */
            let corrected = position == .front ? image.mirrored() : image
            captured?(corrected)
            captured = nil
        }
    }
}

private extension UIImage {
    func mirrored() -> UIImage {
        guard let cgImage else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .leftMirrored)
    }
}

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

struct ProgressCameraView: View {
    @State private var language = LanguageState.shared
    @State private var controller = ProgressCameraController()
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var timerSeconds = 5
    @State private var ghost: Double = 0.25
    @State private var showLibrary = false
    @State private var libraryImage: UIImage?

    var intent: ProgressCaptureIntent
    /// The previous photo in the same pose, shown underneath for alignment.
    var reference: ProgressPhoto?
    let operation: AccountOperationLease
    var onClose: () -> Void

    /// Whether the user has allowed the front camera for progress scans.
    private var allowsFrontCamera: Bool {
        session.data.settings?.addons["allow_front_camera_scanning"]?.boolValue ?? false
    }
    var onCaptured: (UIImage, ProgressCaptureIntent) -> Void

    @Environment(AppSession.self) private var session
    @State private var referenceImage: UIImage?

    @State private var pose: String
    @State private var framing: ProgressPhotoEngine.FramingMode

    init(
        intent: ProgressCaptureIntent,
        reference: ProgressPhoto? = nil,
        operation: AccountOperationLease,
        onClose: @escaping () -> Void,
        onCaptured: @escaping (UIImage, ProgressCaptureIntent) -> Void
    ) {
        self.intent = intent
        self.reference = reference
        self.operation = operation
        self.onClose = onClose
        self.onCaptured = onCaptured
        _pose = State(initialValue: intent.pose)
        _framing = State(initialValue: intent.framing)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewLayer(session: controller.session).ignoresSafeArea()

            if let referenceImage, ghost > 0 {
                Image(uiImage: referenceImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(ghost)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            guides
            chrome
            liveReading

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task {
            /* Honour the setting. It has existed in Settings since the camera
               did, and nothing has ever read it: the scanner opened on the
               front camera regardless of what the switch said. */
            guard session.accountOperationIsCurrent(operation) else { return }
            await controller.start(position: allowsFrontCamera ? .front : .back)
            guard session.accountOperationIsCurrent(operation) else {
                controller.stop()
                return
            }
        }
        .task(id: reference?.id) {
            guard session.accountOperationIsCurrent(operation),
                  let reference else { return }
            do {
                let url = try await session.signedProgressURL(
                    for: reference,
                    thumbnail: false,
                    operation: operation
                )
                let (data, _) = try await URLSession.shared.data(from: url)
                guard session.accountOperationIsCurrent(operation) else { return }
                referenceImage = UIImage(data: data)
            } catch is CancellationError {
                return
            } catch {
                guard session.accountOperationIsCurrent(operation) else { return }
                referenceImage = nil
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            controller.stop()
        }
        .animation(.snappy(duration: 0.2), value: countdown)
        .sheet(isPresented: $showLibrary) {
            ProgressLibraryPicker(image: $libraryImage)
        }
        .onChange(of: libraryImage) { _, image in
            guard session.accountOperationIsCurrent(operation), let image else { return }
            onCaptured(image, resolvedIntent)
        }
    }

    /* The one number that makes two photos comparable, and what the camera
       can actually see. Placed high and out of the guide so it never sits
       over the body being framed. */
    private var liveReading: some View {
        let reading = controller.reading
        return VStack {
            Spacer().frame(height: 108)
            HStack(spacing: 8) {
                if let distance = reading.distanceText {
                    HStack(spacing: 6) {
                        Image(systemName: "ruler")
                            .font(.system(size: 10, weight: .bold))
                        Text(distance)
                            .font(APEXFont.mono(12, weight: .bold))
                        if let hint = reading.placementHint {
                            Text(language.text(hint).uppercased())
                                .font(APEXFont.mono(8, weight: .bold))
                                .tracking(0.8)
                        }
                    }
                    .foregroundStyle(reading.isWellPlaced ? APEXColor.green : Color(red: 0.99, green: 0.90, blue: 0.54))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(.black.opacity(0.45), in: Capsule())
                }
                if reading.subject != .none {
                    HStack(spacing: 6) {
                        Image(systemName: reading.subject.systemImage)
                            .font(.system(size: 10, weight: .bold))
                        Text(language.text(reading.subject.label).uppercased())
                            .font(APEXFont.mono(8, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(.black.opacity(0.45), in: Capsule())
                }
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .animation(.snappy(duration: 0.2), value: reading.subject)
    }

    private var resolvedIntent: ProgressCaptureIntent {
        var next = intent
        next.pose = pose
        next.framing = framing
        return next
    }

    @ViewBuilder
    private var guides: some View {
        switch framing {
        case .full:
            ZStack {
                FullBodyGuideShape().stroke(.white.opacity(0.88), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                FullBodyCentreLine().stroke(Color(red: 0.77, green: 0.71, blue: 0.99).opacity(0.42), style: .init(lineWidth: 1, dash: [5, 8]))
                FullBodyFloorLine().stroke(Color(red: 0.99, green: 0.90, blue: 0.54), style: .init(lineWidth: 2, dash: [7, 7]))
            }
            .padding(.horizontal, 44)
            .padding(.top, 118)
            .padding(.bottom, 168)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) { hint("HEAD AND FEET INSIDE THE GUIDE") }
        case .torso:
            ZStack {
                TorsoGuideShape().stroke(.white.opacity(0.9), style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                TorsoCentreLine().stroke(Color(red: 0.77, green: 0.71, blue: 0.99).opacity(0.48), style: .init(lineWidth: 1.5, dash: [6, 9]))
                TorsoBoundsShape().stroke(Color(red: 0.99, green: 0.90, blue: 0.54).opacity(0.78), style: .init(lineWidth: 1.5, dash: [8, 10]))
            }
            .padding(.horizontal, 24)
            .padding(.top, 130)
            .padding(.bottom, 180)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) { hint("HEAD, SHOULDERS AND WAIST INSIDE THE GUIDE") }
        case .free:
            EmptyView()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(language.text(text).uppercased())
            .font(APEXFont.mono(8, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color(red: 0.99, green: 0.95, blue: 0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.bottom, 150)
            .allowsHitTesting(false)
    }

    private var chrome: some View {
        VStack {
            VStack(spacing: 10) {
                HStack {
                    Button(language.text("Close"), action: closeCamera)
                        .font(APEXFont.body(14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(.black.opacity(0.4), in: Capsule())
                    Spacer()
                    segmented(
                        options: [("FRONT", "front"), ("SIDE", "side"), ("BACK", "back")],
                        selected: pose
                    ) { pose = $0 }
                }
                segmented(
                    options: [
                        ("FULL BODY", ProgressPhotoEngine.FramingMode.full.rawValue),
                        ("TORSO", ProgressPhotoEngine.FramingMode.torso.rawValue),
                        ("FREE", ProgressPhotoEngine.FramingMode.free.rawValue),
                    ],
                    selected: framing.rawValue,
                    tint: Color(red: 0.83, green: 0.78, blue: 1.0)
                ) { raw in
                    if let mode = ProgressPhotoEngine.FramingMode(rawValue: raw) { framing = mode }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    timerPicker
                    if referenceImage != nil { ghostSlider }
                    Button(language.text("Flip camera")) { controller.flip() }
                        .font(APEXFont.body(11, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(language.text("CAMERA ONLY · MICROPHONE OFF").uppercased())
                    .font(APEXFont.mono(8, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(APEXColor.green)

                HStack {
                    Button(language.text("Library")) { showLibrary = true }
                        .font(APEXFont.body(12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .frame(height: 38)
                        .background(.white.opacity(0.15), in: Capsule())
                    Spacer()
                    Button(action: beginCountdown) {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 76, height: 76)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                    }
                    .disabled(!controller.isReady || countdown != nil)
                    .accessibilityLabel(language.format("Take photo in %d seconds", timerSeconds))
                    .accessibilityIdentifier("progress-camera-shutter")
                    Spacer()
                    if allowsFrontCamera {
                        Text(controller.position == .front ? language.text("REAR") : language.text("FRONT"))
                            .font(APEXFont.mono(10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 74, alignment: .trailing)
                    } else {
                        Color.clear.frame(width: 74)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .buttonStyle(.plain)
    }

    private func closeCamera() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        controller.stop()
        onClose()
    }

    private var timerPicker: some View {
        HStack(spacing: 4) {
            ForEach([3, 5, 10], id: \.self) { value in
                Button { timerSeconds = value } label: {
                    Text("\(value)s")
                        .font(APEXFont.mono(11, weight: .bold))
                        .foregroundStyle(timerSeconds == value ? .black : .white.opacity(0.75))
                        .frame(width: 38, height: 32)
                        .background(timerSeconds == value ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: Capsule())
                }
            }
        }
        .padding(3)
        .background(.black.opacity(0.4), in: Capsule())
    }

    private var ghostSlider: some View {
        HStack(spacing: 8) {
            Text(language.text("Ghost"))
                .font(APEXFont.body(11, weight: .bold))
                .foregroundStyle(.white)
            Slider(value: $ghost, in: 0...0.55, step: 0.05)
                .tint(.white)
                .frame(width: 96)
                .accessibilityLabel(language.text("Ghost opacity"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4), in: Capsule())
    }

    private func segmented(
        options: [(String, String)],
        selected: String,
        tint: Color = .white,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.1) { label, value in
                Button { onSelect(value) } label: {
                    Text(language.text(label))
                        .font(APEXFont.mono(10, weight: .bold))
                        .foregroundStyle(selected == value ? .black : .white.opacity(0.72))
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(selected == value ? AnyShapeStyle(tint) : AnyShapeStyle(.clear), in: Capsule())
                }
            }
        }
        .padding(3)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private func beginCountdown() {
        countdownTask?.cancel()
        countdown = timerSeconds
        countdownTask = Task {
            while let value = countdown, value > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard Task.isCancelled == false,
                      session.accountOperationIsCurrent(operation) else { return }
                countdown = value - 1
            }
            guard Task.isCancelled == false,
                  session.accountOperationIsCurrent(operation) else { return }
            countdown = nil
            controller.capture { image in
                guard session.accountOperationIsCurrent(operation) else { return }
                onCaptured(image, resolvedIntent)
            }
        }
    }
}

struct ProgressLibraryPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProgressLibraryPicker
        init(parent: ProgressLibraryPicker) { self.parent = parent }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
