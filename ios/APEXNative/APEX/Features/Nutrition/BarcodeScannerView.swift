@preconcurrency import AVFoundation
import SwiftUI

enum BarcodeScannerPhase: Equatable {
    case scanning
    case lookingUp
    case foodFound
    case message
    case choosingPortion

    var shouldRunCamera: Bool { self == .scanning }

    static func resolve(
        codeCaptured: Bool,
        lookingUp: Bool,
        hasFood: Bool,
        hasMessage: Bool,
        choosingPortion: Bool
    ) -> Self {
        if choosingPortion { return .choosingPortion }
        if hasFood { return .foodFound }
        if hasMessage { return .message }
        if lookingUp || codeCaptured { return .lookingUp }
        return .scanning
    }
}

struct BarcodeResultRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    fileprivate var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * linear(red)) + (0.7152 * linear(green)) + (0.0722 * linear(blue))
    }
}

enum BarcodeFoundFoodPalette {
    static let statsForeground = BarcodeResultRGB(red: 0.98, green: 0.99, blue: 1.00)
    static let statsBackground = BarcodeResultRGB(red: 0.055, green: 0.065, blue: 0.09)

    static var statsContrastRatio: Double {
        let lighter = max(statsForeground.relativeLuminance, statsBackground.relativeLuminance)
        let darker = min(statsForeground.relativeLuminance, statsBackground.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

struct BarcodeScannerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let date: Date
    var onAdd: ((Food, Double, String) -> Void)? = nil
    @State private var code: String?
    @State private var permissionDenied = false
    @State private var food: Food?
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var showPortion = false

    private var scannerPhase: BarcodeScannerPhase {
        BarcodeScannerPhase.resolve(
            codeCaptured: code != nil,
            lookingUp: isLookingUp,
            hasFood: food != nil,
            hasMessage: lookupMessage != nil,
            choosingPortion: showPortion
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if scannerPhase.shouldRunCamera {
                CameraBarcodeScanner(
                    code: $code,
                    permissionDenied: $permissionDenied,
                    isActive: true
                )
                    .ignoresSafeArea()
            }

            LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.black.opacity(0.48), in: Circle())
                    }
                    Spacer()
                    Text(language.text("SCAN FOOD BARCODE"))
                        .font(APEXFont.mono(11))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 46, height: 46)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer()

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(APEXColor.amber, style: StrokeStyle(lineWidth: 3, dash: [25, 8]))
                    .frame(width: 304, height: 194)
                    .overlay {
                        Image(systemName: "barcode")
                            .font(.system(size: 88, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.16))
                    }

                Spacer()

                GlassCard(radius: 28, padding: 19) {
                    VStack(spacing: 8) {
                        if permissionDenied {
                            Text(language.text("Camera access is off"))
                                .font(APEXFont.display(20))
                            Text(language.text("Enable Camera for APEX in Settings to scan food labels."))
                                .font(APEXFont.body(13, weight: .medium))
                                .multilineTextAlignment(.center)
                        } else if isLookingUp {
                            ProgressView()
                            Text(language.text("Reading nutrition data"))
                                .font(APEXFont.display(20))
                            Text(language.text("Checking APEX Food Memory and Open Food Facts"))
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        } else if let food {
                            Text(food.localizedName(language.language))
                                .font(APEXFont.display(20))
                            Text(language.format(
                                "%d kcal · P %d · C %d · F %d per 100",
                                Int((food.kcal100 ?? 0).rounded()),
                                Int((food.protein100 ?? 0).rounded()),
                                Int((food.carbs100 ?? 0).rounded()),
                                Int((food.fat100 ?? 0).rounded())
                            ))
                                .font(APEXFont.mono(11, weight: .bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(BarcodeFoundFoodPalette.statsForeground.color)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    BarcodeFoundFoodPalette.statsBackground.color,
                                    in: Capsule(style: .continuous)
                                )
                                .accessibilityIdentifier("barcode-found-macros")
                            Button(language.text("Choose portion")) { showPortion = true }
                                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
                        } else if let lookupMessage {
                            Text(language.text("Barcode read"))
                                .font(APEXFont.display(20))
                            Text(language.text(lookupMessage))
                                .font(APEXFont.body(12, weight: .medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(APEXColor.secondaryInk)
                            Button(language.text("Scan another")) {
                                code = nil
                                self.lookupMessage = nil
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text(language.text("Hold the barcode inside the frame"))
                                .font(APEXFont.display(18))
                            Text(language.text("APEX detects EAN-8, EAN-13 and UPC labels automatically."))
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(18)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: code) { _, newCode in
            guard let newCode else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task { await lookup(newCode) }
        }
        .sheet(isPresented: $showPortion) {
            if let food {
                ScrollView {
                    FoodAmountSheet(
                        food: food,
                        preference: preference(for: food),
                        onClose: { showPortion = false }
                    ) { amount, unit in
                        onAdd?(food, amount, unit)
                        if onAdd != nil {
                            showPortion = false
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func preference(for food: Food) -> FoodPreference? {
        UUID(uuidString: food.id).flatMap { id in
            session.data.foodPreferences.first { $0.foodID == id }
        }
    }

    @MainActor
    private func lookup(_ barcode: String) async {
        isLookingUp = true
        lookupMessage = nil
        defer { isLookingUp = false }
        do {
            let response = try await session.lookupFood(barcode: barcode)
            if let found = response.food {
                food = found
            } else {
                lookupMessage = response.message ?? "This product is not in the nutrition database yet."
            }
        } catch {
            lookupMessage = "The barcode is valid, but nutrition lookup is unavailable right now. Try again when connected."
        }
    }
}

private struct CameraBarcodeScanner: UIViewControllerRepresentable {
    @Binding var code: String?
    @Binding var permissionDenied: Bool
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        let controller = BarcodeCameraController()
        controller.delegate = context.coordinator
        controller.setCaptureActive(isActive)
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeCameraController, context: Context) {
        context.coordinator.parent = self
        uiViewController.setCaptureActive(isActive)
    }

    static func dismantleUIViewController(
        _ uiViewController: BarcodeCameraController,
        coordinator: Coordinator
    ) {
        uiViewController.setCaptureActive(false)
    }

    final class Coordinator: NSObject, BarcodeCameraControllerDelegate {
        var parent: CameraBarcodeScanner
        init(parent: CameraBarcodeScanner) { self.parent = parent }

        func scannerFound(code: String) {
            guard parent.code == nil else { return }
            parent.code = code
        }

        func scannerPermissionDenied() {
            parent.permissionDenied = true
        }
    }
}

@MainActor
private protocol BarcodeCameraControllerDelegate: AnyObject {
    func scannerFound(code: String)
    func scannerPermissionDenied()
}

private final class BarcodeCameraController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: BarcodeCameraControllerDelegate?
    private let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()
    private let sessionQueue = DispatchQueue(label: "ch.apexperformance.barcode-camera-session")
    private var captureRequested = false
    private var sessionConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        configurePermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setCaptureActive(false)
    }

    func setCaptureActive(_ isActive: Bool) {
        captureRequested = isActive
        guard sessionConfigured else { return }
        let captureSession = session
        sessionQueue.async {
            if isActive {
                if !captureSession.isRunning { captureSession.startRunning() }
            } else if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func configurePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureSession() : self?.delegate?.scannerPermissionDenied()
                }
            }
        default:
            /* viewDidLoad runs inside SwiftUI's representable update. Defer the
               binding write so a previously denied camera permission cannot
               mutate SwiftUI state during that update transaction. */
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.scannerPermissionDenied()
            }
        }
    }

    private func configureSession() {
        guard !sessionConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce]
        sessionConfigured = true
        setCaptureActive(captureRequested)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        delegate?.scannerFound(code: value)
    }
}
