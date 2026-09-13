import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onFocus: (CGPoint) -> Void
    @MainActor final class Coordinator: NSObject {
        var onFocus: (CGPoint) -> Void
        init(onFocus: @escaping (CGPoint) -> Void) { self.onFocus = onFocus }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? Preview else { return }
            onFocus(view.videoLayer.captureDevicePointConverted(fromLayerPoint: recognizer.location(in: view)))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onFocus: onFocus) }
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview(); view.videoLayer.session = session; view.videoLayer.videoGravity = .resizeAspectFill
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        if let connection = view.videoLayer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        return view
    }
    func updateUIView(_ uiView: Preview, context: Context) {
        context.coordinator.onFocus = onFocus
        if let connection = uiView.videoLayer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}

struct CameraView: View {
    var watchName: String
    var coverOnly = false
    var onClose: () -> Void
    var onPhoto: (PhotoDraft) -> Void
    @State private var service = CaptureService()
    @State private var ready = false
    @State private var busy = false
    @State private var hasTorch = false
    @State private var lensDescription = ""
    @State private var torch = false
    @State private var denied = false
    @State private var error: String?
    @State private var visible = false
    var body: some View {
        #if targetEnvironment(simulator) && DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && !ProcessInfo.processInfo.arguments.contains("--real-camera") {
            SimulatorCameraView(coverOnly: coverOnly, onClose: onClose, onPhoto: onPhoto)
        } else { realBody }
        #else
        realBody
        #endif
    }
    private var realBody: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark", action: onClose).labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle()).disabled(busy)
                Spacer()
                VStack { Text(coverOnly ? "Reference photo" : "New reading").font(.headline); Text(watchName).font(.subheadline) }
                Spacer(); Color.clear.frame(width: 22, height: 22)
            }.padding(20)
            ZStack {
                CameraPreview(session: service.session) { point in
                    service.focus(at: point) { message in if let message { error = message } }
                }.allowsHitTesting(ready && !busy)
                    .accessibilityLabel("Camera preview")
                    .accessibilityAction(named: "Focus on the center of the dial") {
                        service.focus(at: CGPoint(x: 0.5, y: 0.5)) { message in if let message { error = message } }
                    }
                RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [32, 100]))
                    .padding(30).accessibilityHidden(true).allowsHitTesting(false)
                if let error {
                    VStack(spacing: 18) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text(error).multilineTextAlignment(.center)
                        if denied {
                            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(.borderedProminent)
                        } else { Button("Try again") { Task { await start() } }.buttonStyle(.borderedProminent) }
                        Text("Watch Box and your saved history are still available.").font(.caption)
                    }.padding(24).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18)).padding(20)
                } else if !ready { ProgressView().tint(.white) }
            }.clipped()
            VStack(spacing: 16) {
                if ready { Text(lensDescription).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                Text(coverOnly ? "This photo will not create a timing reading." : "Phone time is saved with your photo.").font(.subheadline).multilineTextAlignment(.center)
                HStack {
                    if hasTorch {
                        Button(torch ? "Turn torch off" : "Turn torch on", systemImage: torch ? "flashlight.on.fill" : "flashlight.off.fill") {
                            let requested = !torch
                            service.torch(requested) { message in if let message { error = message } else { torch = requested } }
                        }.labelStyle(.iconOnly).font(.title2).frame(width: 50, height: 50).background(.white.opacity(0.1), in: Circle())
                    } else { Color.clear.frame(width: 50) }
                    Spacer()
                    Button {
                        guard ready && !busy else { return }
                        busy = true
                        service.capture { result in
                            busy = false
                            guard visible else { return }
                            do {
                                let photo = try result.get()
                                onPhoto(try PhotoDraft(bytes: photo.bytes, capture: coverOnly ? nil : photo.metadata, source: coverOnly ? .cameraCover : .timing))
                            } catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 3).frame(width: 82, height: 82)
                            Circle().fill(.white).frame(width: 70, height: 70)
                            if busy { ProgressView().tint(.black) }
                        }
                    }.accessibilityLabel("Take photo").accessibilityIdentifier("shutter").disabled(!ready || busy)
                    Spacer(); Color.clear.frame(width: 50)
                }
            }.padding(24)
        }.modifier(CameraSurface()).modifier(CloudEditingGuard())
            .task { visible = true; await start() }
            .onDisappear { visible = false; service.stop() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                ready = false; service.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if visible && !ready { Task { await start() } }
            }
    }
    private func start() async {
        error = nil; denied = false
        let status: AVAuthorizationStatus
        #if targetEnvironment(simulator) && DEBUG
        status = ProcessInfo.processInfo.arguments.contains("--camera-denied") ? .denied : AVCaptureDevice.authorizationStatus(for: .video)
        #else
        status = AVCaptureDevice.authorizationStatus(for: .video)
        #endif
        let allowed: Bool
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        else { allowed = status == .authorized }
        guard visible else { return }
        guard allowed else { denied = true; error = "Camera access is off. Enable it in Settings to take readings."; return }
        service.start { message, supportsTorch, description in error = message; ready = message == nil; hasTorch = supportsTorch; lensDescription = description }
    }
}

struct CaptureFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let watchID: UUID
    let runID: UUID?
    @State private var draft: PhotoDraft?
    @State private var saving = false
    @State private var proposed: WatchTime?
    @State private var jumpWarning = false
    @State private var localError: String?
    private var watchName: String { store.database.watches.first { $0.id == watchID }?.displayName ?? "Watch" }
    var body: some View {
        Group {
            if let draft, let capture = draft.capture {
                let run = store.database.runs.first { $0.id == runID }
                let prior = runID.map { store.database.readings(in: $0) } ?? []
                let prefill = ReadingPrefill.predict(at: capture.reference, readings: prior,
                    clockCompromised: (run?.clockCompromised ?? false) || capture.clockDiscontinuity)
                NavigationStack {
                    TimeEntryView(image: draft.image, capture: capture,
                                  initial: .at(prefill.instant, offset: run?.basisUTCOffset ?? capture.localUTCOffset),
                                  previousOffset: prefill.expectedOffset, saving: saving, buttonTitle: "Save reading",
                                  prefillDescription: prefill.explanation) { value in
                        proposed = value
                        if runID != nil && abs((value.instant?.timeIntervalSince(capture.reference) ?? 0) - prefill.expectedOffset) > 120 { jumpWarning = true }
                        else { save(value) }
                    }.navigationTitle("Read the dial").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                            ToolbarItem(placement: .topBarTrailing) { Button("Retake") { self.draft = nil }.disabled(saving) }
                        }
                }
            } else {
                CameraView(watchName: watchName, onClose: { dismiss() }, onPhoto: { draft = $0 })
            }
        }.confirmationDialog("That differs a lot from the watch’s expected time. Check your entry. Were the hands reset or did the watch stop?", isPresented: $jumpWarning, titleVisibility: .visible) {
            Button("Entry is correct — keep same run") { if let proposed { save(proposed) } }
            Button("Hands reset / stopped — new run") { if let proposed { save(proposed, reason: "Hands reset or watch stopped") } }
            Button("Check entry", role: .cancel) {}
        }.alert("Reading not saved", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button("OK") { localError = nil }
        } message: { Text(localError ?? "Your draft is still here. Try saving again.") }
    }
    private func save(_ entered: WatchTime, reason: String? = nil) {
        guard !saving, let draft else { return }; saving = true
        let success = store.perform {
            try $0.saveReading(id: draft.id, watchID: watchID, expectedRunID: runID,
                               photo: draft.asset(watchID: watchID), bytes: draft.bytes, thumbnail: draft.thumbnail,
                               entered: entered, newRunReason: reason)
        }
        if success { dismiss() }
        else { saving = false; localError = store.failure; store.failure = nil }
    }
}
