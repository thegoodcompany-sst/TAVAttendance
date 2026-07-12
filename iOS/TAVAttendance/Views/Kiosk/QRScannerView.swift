import AVFoundation
import SwiftUI

/// Kiosk QR sign-in scanner (flag `qr_sign_in`). The QR payload is a student UUID;
/// `onScan` runs the same sign-in path as tapping the student's card and returns a
/// feedback line. Scanning continues after each result so a queue of students can
/// scan without re-opening the sheet.
struct QRScannerSheet: View {
    let onScan: (String) async -> String

    @Environment(\.dismiss) private var dismiss
    @State private var authorized: Bool? = nil
    @State private var feedback: String? = nil
    @State private var isProcessing = false
    @State private var lastPayload: String? = nil
    @State private var lastScanAt = Date.distantPast

    var body: some View {
        NavigationStack {
            ZStack {
                switch authorized {
                case true:
                    QRCameraPreview { payload in handleScan(payload) }
                        .ignoresSafeArea()
                    VStack {
                        Spacer()
                        if let feedback {
                            Text(feedback)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.black.opacity(0.7), in: Capsule())
                                .padding(.bottom, 32)
                        }
                    }
                case false:
                    ContentUnavailableView(
                        "Camera Access Needed",
                        systemImage: "camera.fill",
                        description: Text("Allow camera access for TAVAttendance in Settings to scan student QR codes.")
                    )
                default:
                    ProgressView()
                }
            }
            .navigationTitle("Scan to Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized:    authorized = true
                case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
                default:             authorized = false
                }
            }
        }
    }

    private func handleScan(_ payload: String) {
        guard !isProcessing else { return }
        // Debounce: the camera reports the same code many times per second while
        // it stays in frame; only re-process a repeat after a short cooldown.
        let now = Date()
        guard payload != lastPayload || now.timeIntervalSince(lastScanAt) > 2 else { return }
        lastPayload = payload
        lastScanAt = now
        isProcessing = true
        Task {
            feedback = await onScan(payload)
            isProcessing = false
        }
    }
}

// MARK: - Camera preview (AVCaptureMetadataOutput, .qr only)

private struct QRCameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onCode: onCode)
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onCode: (String) -> Void
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // startRunning blocks; keep it off the main thread per AVFoundation guidance.
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = metadataObjects
            .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
            .first(where: { $0.type == .qr })?.stringValue else { return }
        onCode(code)
    }
}
