@preconcurrency import AVFoundation
import SwiftUI

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraBarcodeScanner(code: $code, permissionDenied: $permissionDenied)
                .ignoresSafeArea()

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
                    Text("SCAN FOOD BARCODE")
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
                            Text("Camera access is off")
                                .font(APEXFont.display(20))
                            Text("Enable Camera for APEX in Settings to scan food labels.")
                                .font(APEXFont.body(13, weight: .medium))
                                .multilineTextAlignment(.center)
                        } else if isLookingUp {
                            ProgressView()
                            Text("Reading nutrition data")
                                .font(APEXFont.display(20))
                            Text("Checking APEX Food Memory and Open Food Facts")
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        } else if let food {
                            Text(food.name)
                                .font(APEXFont.display(20))
                            Text(language.format(
                                "%d kcal · P %d · C %d · F %d per 100",
                                Int((food.kcal100 ?? 0).rounded()),
                                Int((food.protein100 ?? 0).rounded()),
                                Int((food.carbs100 ?? 0).rounded()),
                                Int((food.fat100 ?? 0).rounded())
                            ))
                                .font(APEXFont.body(12, weight: .medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(APEXColor.secondaryInk)
                            Button("Choose portion") { showPortion = true }
                                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
                        } else if let lookupMessage {
                            Text("Barcode read")
                                .font(APEXFont.display(20))
                            Text(language.text(lookupMessage))
                                .font(APEXFont.body(12, weight: .medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(APEXColor.secondaryInk)
                            Button("Scan another") {
                                code = nil
                                self.lookupMessage = nil
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text("Hold the barcode inside the frame")
                                .font(APEXFont.display(18))
                            Text("APEX detects EAN-8, EAN-13 and UPC labels automatically.")
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
                FoodPortionSheet(food: food, date: date) { food, amount, unit in
                    onAdd?(food, amount, unit)
                    if onAdd != nil { dismiss() }
                }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
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

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        let controller = BarcodeCameraController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeCameraController, context: Context) {}

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
        session.stopRunning()
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
        default: delegate?.scannerPermissionDenied()
        }
    }

    private func configureSession() {
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
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        delegate?.scannerFound(code: value)
    }
}
