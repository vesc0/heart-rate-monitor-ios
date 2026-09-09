//
//  PPGMeasurementViewModel.swift
//  Heart Rate Monitor
//

import AVFoundation
import SwiftUI

// Shared lifecycle for the camera measurements: calibrate on the first few beats,
// then collect RR intervals for `measureDuration` seconds. Subclasses decide what
// to do with the result.
class PPGMeasurementViewModel: ObservableObject {

    @Published var phase: SessionPhase = .idle
    @Published var currentBPM: Int?
    @Published var secondsLeft: Int = 0
    @Published var heartScale: CGFloat = 1.0
    @Published var canShowBPM: Bool = false
    @Published var errorMessage: String?
    @Published var flashUnavailableAlert: String?

    var session: AVCaptureSession { capture.session }

    // Beat-to-beat intervals collected during the measurement window.
    private(set) var intervals: [TimeInterval] = []

    private let capture = PPGCaptureSession()
    private var detector = PulseDetector()
    private let measureDuration: TimeInterval
    private let bpmRevealAfter: TimeInterval = 4
    private let calibrationBeatsRequired = 4

    private var calibrationBeats = 0
    private var measurementStart: CFTimeInterval?
    private var stoppedEarly = false

    private var phaseTimer: Timer?
    private var countdownTimer: Timer?
    private var bpmRevealTimer: Timer?

    init(measureDuration: TimeInterval) {
        self.measureDuration = measureDuration

        capture.onSample = { [weak self] redMean in self?.handle(redMean) }
        capture.onError = { [weak self] message in self?.errorMessage = message }
        capture.onTorchUnavailable = { [weak self] in
            self?.flashUnavailableAlert = "Flash is unavailable. Your device may be too hot. Please let it cool down or move to a cooler environment."
            self?.errorMessage = "Flash is unavailable due to device temperature. Please cool down your device."
        }
    }

    deinit {
        capture.stop()
        invalidateTimers()
    }

    // Called on the main thread once a measurement completes normally.
    func measurementDidFinish() {}

    func reset() {
        currentBPM = nil
        secondsLeft = 0
        heartScale = 1.0
        errorMessage = nil
        canShowBPM = false

        detector.reset()
        intervals.removeAll()
        calibrationBeats = 0
        measurementStart = nil
    }

    // MARK: - Lifecycle

    func startSession() {
        guard phase == .idle || phase == .finished else { return }
        reset()
        stoppedEarly = false
        phase = .measuring
        capture.start()
    }

    func stopSessionEarly() {
        stoppedEarly = true
        phase = .idle
        capture.stop()
        invalidateTimers()
    }

    private func endSession() {
        if stoppedEarly {
            currentBPM = nil
            phase = .idle
        } else {
            currentBPM = Self.bpm(from: intervals)
            phase = .finished
            measurementDidFinish()
        }
        capture.stop()
        invalidateTimers()
    }

    // MARK: - Beats

    private func handle(_ redMean: Double) {
        guard phase == .measuring else { return }
        let now = CACurrentMediaTime()
        guard let interval = detector.process(redMean, at: now) else { return }

        if let start = measurementStart, now >= start {
            intervals.append(interval)
            currentBPM = Self.bpm(from: intervals.suffix(5))
        } else {
            calibrationBeats += 1
            if calibrationBeats >= calibrationBeatsRequired && measurementStart == nil {
                beginMeasuring(at: now)
            }
        }
        pulseHeart()
    }

    // Calibration is done; start the window from a clean slate.
    private func beginMeasuring(at time: CFTimeInterval) {
        measurementStart = time
        intervals.removeAll()
        currentBPM = nil
        canShowBPM = false

        secondsLeft = Int(measureDuration)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            secondsLeft -= 1
            if secondsLeft <= 0 { timer.invalidate() }
        }
        phaseTimer = Timer.scheduledTimer(withTimeInterval: measureDuration, repeats: false) { [weak self] _ in
            self?.endSession()
        }
        bpmRevealTimer = Timer.scheduledTimer(withTimeInterval: bpmRevealAfter, repeats: false) { [weak self] _ in
            self?.canShowBPM = true
        }
    }

    private func invalidateTimers() {
        [phaseTimer, countdownTimer, bpmRevealTimer].forEach { $0?.invalidate() }
        phaseTimer = nil
        countdownTimer = nil
        bpmRevealTimer = nil
    }

    private func pulseHeart() {
        withAnimation(.easeInOut(duration: 0.12)) { heartScale = 1.2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.12)) { self.heartScale = 1.0 }
        }
    }

    static func bpm(from intervals: some Collection<TimeInterval>) -> Int? {
        guard !intervals.isEmpty else { return nil }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        return average > 0 ? Int(60.0 / average) : nil
    }
}
