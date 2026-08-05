import AVFoundation
import Observation

@Observable
final class CameraViewModel: NSObject {
    let session = AVCaptureSession()

    private(set) var isRecording = false
    private(set) var isAuthorized = false
    private(set) var setupError: String?

    var onVideoSaved: ((URL) -> Void)?

    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.toshivlog.camera.session")
    private var currentPosition: AVCaptureDevice.Position = .back

    func start() {
        sessionQueue.async { [weak self] in
            self?.checkAuthorizationAndConfigure()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func switchCamera() {
        currentPosition = currentPosition == .back ? .front : .back
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    func toggleRecording() {
        if isRecording {
            movieOutput.stopRecording()
        } else {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func checkAuthorizationAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.sessionQueue.async { self.configureSession() }
                } else {
                    Task { @MainActor in self.isAuthorized = false }
                }
            }
        default:
            Task { @MainActor in self.isAuthorized = false }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
            let videoInput = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(videoInput)
        else {
            Task { @MainActor in self.setupError = "カメラを初期化できませんでした" }
            return
        }
        session.addInput(videoInput)

        if let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.startRunning()

        Task { @MainActor in
            self.isAuthorized = true
            self.setupError = nil
        }
    }
}

extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in self.isRecording = true }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            if error == nil {
                self.onVideoSaved?(outputFileURL)
            }
        }
    }
}
