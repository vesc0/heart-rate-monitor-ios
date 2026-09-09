//
//  PulseDetector.swift
//  Heart Rate Monitor
//

import Foundation

// Turns the camera's red-channel level into beats: EMA smoothing, a rolling
// baseline, then a local maximum above a variance-scaled threshold.
struct PulseDetector {

    // Plausible beat-to-beat range, roughly 40–220 BPM.
    static let minInterval: TimeInterval = 0.27
    static let maxInterval: TimeInterval = 1.50

    private let windowSize = 45   // ~0.75 s at 60 fps
    private var ema: Double?
    private var window: [Double] = []
    private var lastCentered: Double = 0
    private var lastPeakTime: CFTimeInterval?

    mutating func reset() { self = PulseDetector() }

    // Returns the interval since the previous beat when this sample completes one.
    mutating func process(_ redMean: Double, at time: CFTimeInterval) -> TimeInterval? {
        ema = 0.2 * redMean + 0.8 * (ema ?? redMean)
        let value = ema ?? redMean

        window.append(value)
        if window.count > windowSize { window.removeFirst() }
        let mean = window.reduce(0, +) / Double(window.count)
        let centered = value - mean

        let variance = window.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(max(1, window.count - 1))
        let threshold = max(0.5 * sqrt(variance), 0.5)

        let isPeak = (centered - lastCentered) <= 0 && lastCentered > threshold
        lastCentered = centered
        guard isPeak else { return nil }

        // A peak always advances the reference point, even when the interval it
        // produces is implausible and gets discarded.
        defer { lastPeakTime = time }
        guard let last = lastPeakTime else { return nil }
        let interval = time - last
        return (Self.minInterval...Self.maxInterval).contains(interval) ? interval : nil
    }
}
