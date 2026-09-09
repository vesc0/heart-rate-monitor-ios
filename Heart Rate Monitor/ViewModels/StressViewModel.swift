//
//  StressViewModel.swift
//  Heart Rate Monitor
//
//  Created by Vesco on 3/1/26.
//

import Foundation

// A 60-second window, long enough for the frequency-domain HRV features the
// stress model expects.
final class StressViewModel: PPGMeasurementViewModel {

    // Populated once the API responds.
    @Published var stressResult: StressPredictResponse?
    @Published var isPredicting = false

    private let api = APIService.shared

    init() { super.init(measureDuration: 60) }

    override func reset() {
        super.reset()
        stressResult = nil
        isPredicting = false
    }

    // MARK: - Stress prediction

    override func measurementDidFinish() {
        guard let features = computeHRVFeatures() else {
            errorMessage = "Not enough beats to analyze. Try again."
            return
        }

        isPredicting = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.api.predictStress(features: features)
                self.stressResult = result
            } catch {
                self.errorMessage = "Prediction failed: \(error.localizedDescription)"
            }
            self.isPredicting = false
        }
    }

    // Mirrors the training pipeline's clean(): drop non-physiological and locally
    // deviant intervals, reporting which surviving pairs are still adjacent.
    private static func cleanRR(_ rr: [Double]) -> (values: [Double], adjacent: [Bool]) {
        var ok = rr.map { $0 >= 300 && $0 <= 2000 }
        let physiological = rr.indices.filter { ok[$0] }
        if physiological.count >= 5 {
            let surviving = physiological.map { rr[$0] }
            for (i, index) in physiological.enumerated() {
                let reference = medianOfFive(surviving, at: i)
                if abs(rr[index] - reference) > 0.2 * reference { ok[index] = false }
            }
        }
        let kept = rr.indices.filter { ok[$0] }
        return (kept.map { rr[$0] }, zip(kept, kept.dropFirst()).map { $1 == $0 + 1 })
    }

    // Averages the middle pair on even counts, as the training pipeline does.
    private static func median(_ x: [Double]) -> Double {
        let s = x.sorted()
        return x.count % 2 == 0 ? (s[x.count / 2 - 1] + s[x.count / 2]) / 2 : s[x.count / 2]
    }

    private static func medianOfFive(_ x: [Double], at i: Int) -> Double {
        (-2...2).map { i + $0 >= 0 && i + $0 < x.count ? x[i + $0] : 0 }.sorted()[2]
    }

    // Build a StressPredictRequest from the collected RR intervals.
    private func computeHRVFeatures() -> StressPredictRequest? {
        let (rr, adjacent) = Self.cleanRR(intervals.map { $0 * 1000.0 })
        guard rr.count >= 30 else { return nil }

        // Successive differences, never taken across a discarded beat.
        let diffs = adjacent.indices.filter { adjacent[$0] }.map { rr[$0 + 1] - rr[$0] }
        guard diffs.count > 1 else { return nil }

        let n = Double(rr.count)
        let meanRR   = rr.reduce(0, +) / n
        let medianRR = Self.median(rr)

        let variance = rr.reduce(0.0) { $0 + pow($1 - meanRR, 2) } / (n - 1)
        let sdnn     = sqrt(variance)
        let cvRR     = meanRR > 0 ? sdnn / meanRR : 0

        let rmssd = sqrt(diffs.reduce(0.0) { $0 + $1 * $1 } / Double(diffs.count))
        let pnn50 = Double(diffs.filter { abs($0) > 50 }.count) / Double(diffs.count) * 100
        let pnn20 = Double(diffs.filter { abs($0) > 20 }.count) / Double(diffs.count) * 100

        // Heart rate stats (from each RR interval)
        let hrs = rr.map { 60000.0 / $0 }
        let meanHR  = hrs.reduce(0, +) / Double(hrs.count)
        let minHR   = hrs.min() ?? 0
        let maxHR   = hrs.max() ?? 0
        let hrRange = maxHR - minHR
        let stdHR: Double = {
            guard hrs.count > 1 else { return 0 }
            let m = meanHR
            let v = hrs.reduce(0.0) { $0 + pow($1 - m, 2) } / Double(hrs.count - 1)
            return sqrt(v)
        }()

        // Frequency-domain HRV (Lomb-Scargle approximation via simple PSD)
        var lfPower = 0.0, hfPower = 0.0, lfHfRatio = 0.0
        var totalPower = 0.0, lfNorm = 0.0

        if rr.count >= 20 {
            let rrSec = rr.map { $0 / 1000.0 }
            var tRR = [Double]()
            var cumulative = 0.0
            for r in rrSec {
                cumulative += r
                tRR.append(cumulative)
            }
            // Subtract first to start at 0
            let t0 = tRR[0]
            tRR = tRR.map { $0 - t0 }

            // Interpolate to uniform 4 Hz
            let fs = 4.0
            let tMax = tRR.last ?? 0
            let nSamples = Int(tMax * fs)
            if nSamples > 10 {
                var uniform = [Double]()
                for i in 0..<nSamples {
                    let t = Double(i) / fs
                    // Linear interpolation
                    var idx = 0
                    while idx < tRR.count - 1 && tRR[idx + 1] < t { idx += 1 }
                    if idx >= tRR.count - 1 {
                        uniform.append(rr.last ?? meanRR)
                    } else {
                        let frac = (t - tRR[idx]) / max(tRR[idx + 1] - tRR[idx], 1e-9)
                        uniform.append(rr[idx] + frac * (rr[min(idx + 1, rr.count - 1)] - rr[idx]))
                    }
                }
                // Detrend
                let uMean = uniform.reduce(0, +) / Double(uniform.count)
                let detrended = uniform.map { $0 - uMean }

                // Simple DFT power spectrum (enough for LF/HF bands)
                let N = detrended.count
                let freqRes = fs / Double(N)
                var psd = [Double](repeating: 0, count: N / 2 + 1)
                for k in 0...N/2 {
                    var realPart = 0.0, imagPart = 0.0
                    for ni in 0..<N {
                        let angle = -2.0 * .pi * Double(k) * Double(ni) / Double(N)
                        realPart += detrended[ni] * cos(angle)
                        imagPart += detrended[ni] * sin(angle)
                    }
                    psd[k] = (realPart * realPart + imagPart * imagPart) / (fs * Double(N))
                }

                // Integrate LF (0.04–0.15 Hz) and HF (0.15–0.40 Hz)
                for k in 0..<psd.count {
                    let freq = Double(k) * freqRes
                    if freq >= 0.04 && freq < 0.15 { lfPower += psd[k] * freqRes }
                    if freq >= 0.15 && freq < 0.40 { hfPower += psd[k] * freqRes }
                }
                totalPower = lfPower + hfPower
                lfHfRatio = hfPower > 0 ? lfPower / hfPower : 0
                lfNorm = totalPower > 0 ? lfPower / totalPower * 100 : 0
            }
        }

        // Nonlinear: Poincaré SD1 = SDSD/√2, matching the trained features.
        let diffMean = diffs.reduce(0, +) / Double(diffs.count)
        let sdsd = sqrt(diffs.reduce(0.0) { $0 + pow($1 - diffMean, 2) } / Double(diffs.count - 1))
        let sd1 = sdsd / sqrt(2.0)
        let sd2Sq = 2.0 * sdnn * sdnn - sd1 * sd1
        let sd2: Double = sd2Sq > 0 ? sqrt(sd2Sq) : 0
        let sdRatio: Double = sd1 > 0 ? sd2 / sd1 : 0

        return StressPredictRequest(
            sdnn:       sdnn,
            medianRR:   medianRR,
            cvRR:       cvRR,
            rmssd:      rmssd,
            pnn50:      pnn50,
            pnn20:      pnn20,
            meanHR:     meanHR,
            stdHR:      stdHR,
            minHR:      minHR,
            maxHR:      maxHR,
            hrRange:    hrRange,
            lfPower:    lfPower,
            hfPower:    hfPower,
            lfHfRatio:  lfHfRatio,
            totalPower: totalPower,
            lfNorm:     lfNorm,
            sd1:        sd1,
            sd2:        sd2,
            sdRatio:    sdRatio
        )
    }
}
