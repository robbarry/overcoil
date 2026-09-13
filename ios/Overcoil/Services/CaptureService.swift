@preconcurrency import AVFoundation
import Foundation
import UIKit

struct CapturedPhoto: Sendable {
    var bytes: Data
    var metadata: CaptureMetadata
}

// All camera mutation runs on queue, never on the UI thread. This object's only
// cross-queue exposure is the session used by AVCaptureVideoPreviewLayer.
final class CaptureService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.robbarry.overcoil.camera")
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var lensDescription = "Standard lens"
    private var busy = false
    private var requestID: Int64?
    private var anchor: ClockAnchor?
    private var captureContinuity: (UUID, Bool)?
    private var pending: CapturedPhoto?
    private var failure: String?
    private var callback: (@MainActor @Sendable (Result<CapturedPhoto, CaptureFailure>) -> Void)?

    struct CaptureFailure: LocalizedError, Sendable {
        var message: String
        var errorDescription: String? { message }
    }

    static func sampleAnchor() -> ClockAnchor {
        let host = CMClockGetHostTimeClock()
        let a = CMTimeGetSeconds(CMClockGetTime(host))
        let wall = Date()
        let b = CMTimeGetSeconds(CMClockGetTime(host))
        return ClockAnchor(hostSeconds: (a + b) / 2, wall: wall, bracketSeconds: b - a)
    }

    func start(completion: @escaping @MainActor @Sendable (String?, Bool, String) -> Void) {
        queue.async { [self] in
            do {
                if !configured {
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    session.sessionPreset = .photo
                    guard let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw CaptureFailure(message: "A rear camera is not available on this device.")
                    }
                    let ultra = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                    let closeUp = ultra.map {
                        CaptureLensPolicy.preferUltraWide(ultraFocusMM: $0.minimumFocusDistance,
                            ultraHasAutofocus: $0.isFocusModeSupported(.continuousAutoFocus), wideFocusMM: wide.minimumFocusDistance)
                    } ?? false
                    let camera = closeUp ? ultra! : wide
                    lensDescription = closeUp ? "Close-up lens · tap the dial to focus" : "Standard lens · tap the dial to focus"
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        throw CaptureFailure(message: "The camera could not be configured.")
                    }
                    session.addInput(input); session.addOutput(output)
                    try camera.lockForConfiguration()
                    if closeUp { camera.videoZoomFactor = min(2, camera.maxAvailableVideoZoomFactor) }
                    if camera.isFocusPointOfInterestSupported { camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                    if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                    if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                    if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { camera.whiteBalanceMode = .continuousAutoWhiteBalance }
                    camera.unlockForConfiguration()
                    device = camera
                    output.maxPhotoQualityPrioritization = .speed
                    output.isLivePhotoCaptureEnabled = false
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    configured = true
                }
                if !session.isRunning { session.startRunning() }
                let running = session.isRunning
                let torch = device?.hasTorch == true
                let description = lensDescription
                Task { @MainActor in completion(running ? nil : "The camera is unavailable. Close and try again.", torch, description) }
            } catch {
                if !configured {
                    session.beginConfiguration()
                    for input in session.inputs { session.removeInput(input) }
                    for output in session.outputs { session.removeOutput(output) }
                    session.commitConfiguration()
                }
                let message = error.localizedDescription
                Task { @MainActor in completion(message, false, "") }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if let device, device.hasTorch {
                do { try device.lockForConfiguration(); device.torchMode = .off; device.unlockForConfiguration() }
                catch { /* Stopping the session must still proceed if torch configuration fails. */ }
            }
            if session.isRunning { session.stopRunning() }
        }
    }

    func focus(at point: CGPoint, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard !busy, let device else { return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                Task { @MainActor in completion(nil) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in completion(message) }
            }
        }
    }

    func torch(_ enabled: Bool, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        queue.async { [self] in
            do {
                guard let device, device.hasTorch else { return }
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if enabled { try device.setTorchModeOn(level: 0.3) } else { device.torchMode = .off }
                Task { @MainActor in completion(nil) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in completion(message) }
            }
        }
    }

    func capture(completion: @escaping @MainActor @Sendable (Result<CapturedPhoto, CaptureFailure>) -> Void) {
        queue.async { [self] in
            guard !busy else { return }
            guard session.isRunning else {
                Task { @MainActor in completion(.failure(CaptureFailure(message: "Camera is not running. Please try again."))) }; return
            }
            busy = true; pending = nil; failure = nil; callback = completion
            let pre = Self.sampleAnchor()
            anchor = pre
            captureContinuity = ClockContinuity.shared.inspect(pre)
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.flashMode = .off
            settings.photoQualityPrioritization = .speed
            requestID = settings.uniqueID
            let expectedID = settings.uniqueID
            output.capturePhoto(with: settings, delegate: self)
            queue.asyncAfter(deadline: .now() + 25) { [self] in
                guard busy, requestID == expectedID else { return }
                let finish = callback
                busy = false; callback = nil; pending = nil; anchor = nil; captureContinuity = nil; requestID = nil
                Task { @MainActor in finish?(.failure(CaptureFailure(message: "Capture timed out. No reading was saved. Please try again."))) }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Read timestamp and clock together, on AVFoundation's callback. File data
        // processing time is never used as the reference instant.
        let capturedID = photo.resolvedSettings.uniqueID
        let timestamp = photo.timestamp
        let clock = session.synchronizationClock
        let host = clock.map { CMSyncConvertTime(timestamp, from: $0, to: CMClockGetHostTimeClock()) }
        let bytes = photo.fileDataRepresentation()
        let post = Self.sampleAnchor()
        let errorText = error?.localizedDescription
        queue.async { [self] in
            guard busy, requestID == capturedID else { return }
            if let errorText { failure = errorText; return }
            guard timestamp.isValid, timestamp.isNumeric, timestamp.timescale > 0,
                  let host, host.isValid, host.isNumeric,
                  let bytes, !bytes.isEmpty, let pre = anchor, let (continuity, changed) = captureContinuity else {
                failure = "The photo or its capture timestamp is unavailable. Please retake it."; return
            }
            let seconds = CMTimeGetSeconds(host)
            guard seconds.isFinite, abs(seconds - pre.hostSeconds) < 60 else {
                failure = "The capture clock could not be aligned. Please retake the photo."; return
            }
            guard ClockContinuity.shared.isCurrent(continuity) else {
                failure = "Capture was interrupted when the app left the foreground. Please retake it."; return
            }
            let residual = pre.residual(to: post)
            let reference = pre.wallTime(for: seconds)
            pending = CapturedPhoto(bytes: bytes, metadata: CaptureMetadata(
                reference: reference, localUTCOffset: TimeZone.current.secondsFromGMT(for: reference),
                rawValue: timestamp.value, rawTimescale: timestamp.timescale, rawEpoch: timestamp.epoch,
                hostSeconds: seconds, anchorHostSeconds: pre.hostSeconds, anchorWall: pre.wall,
                anchorBracketSeconds: pre.bracketSeconds, mappingResidualSeconds: residual,
                continuityID: continuity, clockDiscontinuity: changed || abs(residual) > 0.5 || pre.bracketSeconds > 0.1,
                pipeline: "\(device?.deviceType.rawValue ?? "unknown")/jpeg/speed/flash-off/no-live-photo", torchEnabled: device?.torchMode == .on,
                minimumFocusDistanceMM: device?.minimumFocusDistance, videoZoomFactor: device.map { Double($0.videoZoomFactor) }))
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let errorText = error?.localizedDescription
        let capturedID = resolvedSettings.uniqueID
        queue.async { [self] in
            guard busy, requestID == capturedID else { return }
            let result: Result<CapturedPhoto, CaptureFailure>
            if let message = errorText ?? failure { result = .failure(CaptureFailure(message: message)) }
            else if let pending { result = .success(pending) }
            else { result = .failure(CaptureFailure(message: "Capture did not finish. Please try again.")) }
            let finish = callback
            busy = false; callback = nil; pending = nil; anchor = nil; captureContinuity = nil; requestID = nil
            Task { @MainActor in finish?(result) }
        }
    }
}
