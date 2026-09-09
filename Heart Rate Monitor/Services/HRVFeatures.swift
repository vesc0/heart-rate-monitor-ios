//
//  HRVFeatures.swift
//  Heart Rate Monitor
//

import Foundation

// Heart-rate variability features for the stress model. Deliberately a mirror of
// the training pipeline's src/features.py — HRVFeaturesTests pins the two together.
enum HRVFeatures {

    // Mirrors the training pipeline's clean(): drop non-physiological and locally
    // deviant intervals, reporting which surviving pairs are still adjacent.
    static func cleanRR(_ rr: [Double]) -> (values: [Double], adjacent: [Bool]) {
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
    static func median(_ x: [Double]) -> Double {
        let s = x.sorted()
        return x.count % 2 == 0 ? (s[x.count / 2 - 1] + s[x.count / 2]) / 2 : s[x.count / 2]
    }

    static func medianOfFive(_ x: [Double], at i: Int) -> Double {
        (-2...2).map { i + $0 >= 0 && i + $0 < x.count ? x[i + $0] : 0 }.sorted()[2]
    }

    // Build a StressPredictRequest from the collected RR intervals.
    // Feature vector for one measurement window, or nil when too few beats survive.
    static func compute(rrMilliseconds rr0: [Double]) -> StressPredictRequest? {
        let (rr, adjacent) = cleanRR(rr0)
        guard rr.count >= 30 else { return nil }

        // Successive differences, never taken across a discarded beat.
        let diffs = adjacent.indices.filter { adjacent[$0] }.map { rr[$0 + 1] - rr[$0] }
        guard diffs.count > 1 else { return nil }

        let n = Double(rr.count)
        let meanRR   = rr.reduce(0, +) / n
        let medianRR = median(rr)

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

        let spectral = spectrum(of: rr)

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
            lfPower:    spectral.lfPower,
            hfPower:    spectral.hfPower,
            lfHfRatio:  spectral.lfHfRatio,
            totalPower: spectral.totalPower,
            lfNorm:     spectral.lfNorm,
            sd1:        sd1,
            sd2:        sd2,
            sdRatio:    sdRatio
        )
    }

    // MARK: - Frequency domain

    struct Spectrum {
        var lfPower = 0.0
        var hfPower = 0.0
        var lfHfRatio = 0.0
        var totalPower = 0.0
        var lfNorm = 0.0
    }

    private static let samplingRate = 4.0
    private static let segmentLimit = 256

    // Mirrors features.py::_spectral — resample the unevenly spaced RR series onto a
    // uniform 4 Hz grid with a cubic spline, then integrate a Welch periodogram over
    // the LF and HF bands.
    static func spectrum(of rr: [Double]) -> Spectrum {
        var times: [Double] = []
        var elapsed = 0.0
        for interval in rr {
            elapsed += interval
            times.append(elapsed / 1000.0)
        }
        guard let first = times.first, let last = times.last else { return Spectrum() }

        // Built by index rather than accumulation so it matches numpy's arange exactly.
        let step = 1.0 / samplingRate
        let gridCount = Int(((last - first) / step).rounded(.up))
        guard gridCount >= 32 else { return Spectrum() }
        let grid = (0..<gridCount).map { first + Double($0) * step }

        let series = cubicSpline(x: times, y: rr, at: grid)
        let mean = series.reduce(0, +) / Double(series.count)
        let (frequencies, psd) = welch(series.map { $0 - mean },
                                       segmentLength: min(series.count, segmentLimit))

        func power(from low: Double, to high: Double) -> Double {
            let band = frequencies.indices.filter { frequencies[$0] >= low && frequencies[$0] < high }
            guard band.count > 1 else { return 0 }
            // Trapezoidal integration over the selected bins.
            return band.dropLast().enumerated().reduce(0.0) { total, item in
                let (offset, index) = item
                let next = band[offset + 1]
                return total + (psd[index] + psd[next]) * (frequencies[next] - frequencies[index]) / 2
            }
        }

        let lf = power(from: 0.04, to: 0.15)
        let hf = power(from: 0.15, to: 0.40)
        let total = lf + hf
        return Spectrum(
            lfPower: lf,
            hfPower: hf,
            lfHfRatio: hf > 0 ? lf / hf : 0,
            totalPower: total,
            lfNorm: total > 0 ? lf / total * 100 : 0
        )
    }

    // Natural-looking cubic through every point with not-a-knot ends, matching
    // SciPy's interp1d(kind: "cubic").
    static func cubicSpline(x: [Double], y: [Double], at query: [Double]) -> [Double] {
        let n = x.count
        guard n >= 4 else { return query.map { _ in y.first ?? 0 } }
        let h = (0..<n - 1).map { x[$0 + 1] - x[$0] }

        var a = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
        for i in 1..<n - 1 {
            a[i][i - 1] = h[i - 1]
            a[i][i] = 2 * (h[i - 1] + h[i])
            a[i][i + 1] = h[i]
            a[i][n] = 6 * ((y[i + 1] - y[i]) / h[i] - (y[i] - y[i - 1]) / h[i - 1])
        }
        // Not-a-knot: the third derivative stays continuous across the second and
        // second-to-last knots, so the end cubics extend their neighbors.
        a[0][0] = -h[1]; a[0][1] = h[0] + h[1]; a[0][2] = -h[0]
        a[n - 1][n - 3] = -h[n - 2]; a[n - 1][n - 2] = h[n - 3] + h[n - 2]; a[n - 1][n - 1] = -h[n - 3]

        let moments = solve(&a)

        return query.map { t in
            var i = x.count - 2
            if let above = x.firstIndex(where: { $0 > t }) { i = max(0, min(above - 1, n - 2)) }
            let dx = t - x[i]
            let c0 = y[i]
            let c1 = (y[i + 1] - y[i]) / h[i] - h[i] * (2 * moments[i] + moments[i + 1]) / 6
            let c2 = moments[i] / 2
            let c3 = (moments[i + 1] - moments[i]) / (6 * h[i])
            return c0 + dx * (c1 + dx * (c2 + dx * c3))
        }
    }

    // Gaussian elimination with partial pivoting on an augmented matrix.
    private static func solve(_ a: inout [[Double]]) -> [Double] {
        let n = a.count
        for column in 0..<n {
            let pivot = (column..<n).max { abs(a[$0][column]) < abs(a[$1][column]) } ?? column
            a.swapAt(column, pivot)
            let head = a[column][column]
            guard head != 0 else { continue }
            for row in (column + 1)..<n where a[row][column] != 0 {
                let factor = a[row][column] / head
                for k in column...n { a[row][k] -= factor * a[column][k] }
            }
        }
        var result = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var value = a[row][n]
            for k in (row + 1)..<n { value -= a[row][k] * result[k] }
            result[row] = a[row][row] != 0 ? value / a[row][row] : 0
        }
        return result
    }

    // One-sided power spectral density, following scipy.signal.welch's defaults:
    // a periodic Hann window, 50% overlap, and each segment detrended by its mean.
    static func welch(_ samples: [Double], segmentLength: Int) -> (frequencies: [Double], psd: [Double]) {
        let n = segmentLength
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n)) }
        let scale = 1.0 / (samplingRate * window.reduce(0) { $0 + $1 * $1 })
        let bins = n / 2 + 1
        let hop = n - n / 2

        var starts: [Int] = []
        var offset = 0
        while offset + n <= samples.count {
            starts.append(offset)
            offset += hop
        }
        guard !starts.isEmpty else {
            return ((0..<bins).map { Double($0) * samplingRate / Double(n) }, [Double](repeating: 0, count: bins))
        }

        var psd = [Double](repeating: 0, count: bins)
        for start in starts {
            var segment = Array(samples[start..<start + n])
            let mean = segment.reduce(0, +) / Double(n)
            for i in 0..<n { segment[i] = (segment[i] - mean) * window[i] }

            for k in 0..<bins {
                var real = 0.0
                var imaginary = 0.0
                for j in 0..<n {
                    let angle = -2 * Double.pi * Double(k) * Double(j) / Double(n)
                    real += segment[j] * cos(angle)
                    imaginary += segment[j] * sin(angle)
                }
                // Every bin but DC and Nyquist stands in for a mirrored negative one.
                let doubled = k != 0 && !(n % 2 == 0 && k == n / 2)
                psd[k] += (real * real + imaginary * imaginary) * scale * (doubled ? 2 : 1)
            }
        }
        let count = Double(starts.count)
        return ((0..<bins).map { Double($0) * samplingRate / Double(n) }, psd.map { $0 / count })
    }
}
