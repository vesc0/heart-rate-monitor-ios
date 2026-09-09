//
//  PPGCaptureSession.swift
//  Heart Rate Monitor
//

import AVFoundation

// Fingertip PPG capture: rear camera plus torch, reporting the mean red level of
// each frame. Frames are sampled on a private queue; callbacks arrive on the main one.
final class PPGCaptureSession: NSObject {

    let session = AVCaptureSession()

    var onSample: ((Double) -> Void)?
    var onError: ((String) -> Void)?
    var onTorchUnavailable: (() -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "ppg.capture")
    private var device: AVCaptureDevice?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            guard !self.session.inputs.isEmpty else { return }
            self.session.startRunning()
            self.setTorch(on: true)
        }
    }

    func stop() {
        queue.async { [session, device] in
            if let device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
                device.torchMode = .off
                device.unlockForConfiguration()
            }
            session.stopRunning()
        }
    }

    // MARK: - Setup

    private func configureIfNeeded() {
        guard session.inputs.isEmpty else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted { self.start() } else { self.report("Camera access denied.") }
            }
            return
        default:
            report("Camera access denied. Enable it in Settings.")
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .low   // only luminosity is needed, keep it light

        // Closest to the flash first, so the finger is lit evenly.
        let camera = [.builtInUltraWideCamera, .builtInTelephotoCamera, .builtInWideAngleCamera]
            .lazy
            .compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }
            .first

        guard let camera,
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            report("No back camera available.")
            return
        }
        session.addInput(input)
        device = camera

        // BGRA so the red channel can be read straight out of the buffer.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            report("Cannot add video output.")
            return
        }
        session.addOutput(output)

        if (try? camera.lockForConfiguration()) != nil {
            if let range = camera.activeFormat.videoSupportedFrameRateRanges.first {
                let target = min(max(30.0, range.minFrameRate), range.maxFrameRate)
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(target))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(target))
            }
            camera.unlockForConfiguration()
        }
    }

    private func setTorch(on: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            // A moderate level keeps the device cooler over a long session.
            if on { try device.setTorchModeOn(level: min(0.7, AVCaptureDevice.maxAvailableTorchLevel)) }
            else { device.torchMode = .off }
            device.unlockForConfiguration()
        } catch {
            if on { DispatchQueue.main.async { self.onTorchUnavailable?() } }
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.onError?(message) }
    }
}

// MARK: - Frames to red level

extension PPGCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return }

        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)

        // Every 8th pixel in both directions: plenty for a whole-frame average.
        var sum = 0.0
        var count = 0
        for y in stride(from: 0, to: height, by: 8) {
            let row = base + y * bytesPerRow
            for x in stride(from: 0, to: width * 4, by: 32) {
                sum += Double(row[x + 2])   // R in BGRA
                count += 1
            }
        }
        guard count > 0 else { return }

        let redMean = sum / Double(count)
        DispatchQueue.main.async { self.onSample?(redMean) }
    }
}
