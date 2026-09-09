//
//  HRVFeaturesTests.swift
//  Heart Rate MonitorTests
//

import XCTest
@testable import Heart_Rate_Monitor

// The app re-implements the training pipeline's feature extraction in Swift. If the
// two drift apart the model is scored on inputs it was never trained on, which is
// silent and hard to spot in the UI. These fixtures pin them together.
//
// Regenerating the expected values defeats the purpose: they came from
// `src/features.py` in the HeartRateMonitor ML repo for this exact input and are
// only ever changed alongside a deliberate change to the training pipeline.
final class HRVFeaturesTests: XCTestCase {

    // A minute of beats quantized to 30 fps, with two deliberate artifacts: an
    // interval below the physiological floor, and a merged beat that only the
    // local-median filter catches.
    private static let rrMilliseconds: [Double] = [
        833.3325, 833.3325, 833.3325, 799.9992, 799.9992, 799.9992,
        833.3325, 799.9992, 866.6658, 833.3325, 833.3325, 833.3325,
        866.6658, 866.6658, 866.6658, 833.3325, 833.3325, 250.0,
        833.3325, 866.6658, 833.3325, 833.3325, 833.3325, 833.3325,
        799.9992, 833.3325, 799.9992, 833.3325, 866.6658, 866.6658,
        799.9992, 833.3325, 833.3325, 833.3325, 833.3325, 866.6658,
        833.3325, 866.6658, 833.3325, 833.3325, 1580.0, 833.3325,
        833.3325, 833.3325, 799.9992, 799.9992, 799.9992, 766.6659,
        799.9992, 799.9992, 799.9992, 833.3325, 799.9992, 799.9992,
        799.9992, 766.6659, 799.9992, 799.9992, 799.9992, 799.9992,
        799.9992, 799.9992, 799.9992, 833.3325, 799.9992, 799.9992,
        799.9992, 766.6659, 799.9992, 799.9992, 799.9992, 833.3325,
    ]

    private static let expected: [String: Double] = [
        "sdnn": 25.488078251722186,
        "median_rr": 833.3325,
        "cv_rr": 0.031046994114637155,
        "rmssd": 25.103409347397125,
        "pnn50": 2.9850746268656714,
        "pnn20": 47.76119402985074,
        "mean_hr": 73.15520932338899,
        "std_hr": 2.2657185357532903,
        "min_hr": 69.23083846160769,
        "max_hr": 78.26094782616522,
        "hr_range": 9.030109364557532,
        "lf_power": 99.29518469892538,
        "hf_power": 137.61423673832462,
        "lf_hf_ratio": 0.7215473271688928,
        "total_power": 236.90942143725,
        "lf_norm": 41.912720944796035,
        "sd1": 17.884761114842995,
        "sd2": 31.295679986171045,
        "sd_ratio": 1.7498517193052137,
    ]

    // Long enough that Welch averages two overlapping segments rather than one.
    private static let longRRMilliseconds: [Double] = [
        766.6659, 799.9992, 799.9992, 799.9992, 799.9992, 799.9992,
        799.9992, 799.9992, 833.3325, 799.9992, 799.9992, 799.9992,
        799.9992, 799.9992, 799.9992, 799.9992, 799.9992, 766.6659,
        766.6659, 733.3326, 766.6659, 733.3326, 733.3326, 766.6659,
        766.6659, 766.6659, 766.6659, 733.3326, 733.3326, 733.3326,
        733.3326, 733.3326, 733.3326, 733.3326, 699.9993, 733.3326,
        766.6659, 699.9993, 733.3326, 733.3326, 733.3326, 733.3326,
        733.3326, 699.9993, 733.3326, 733.3326, 733.3326, 733.3326,
        733.3326, 699.9993, 666.666, 699.9993, 699.9993, 699.9993,
        699.9993, 733.3326, 733.3326, 699.9993, 733.3326, 733.3326,
        699.9993, 733.3326, 733.3326, 766.6659, 733.3326, 733.3326,
        766.6659, 766.6659, 733.3326, 766.6659, 766.6659, 799.9992,
        766.6659, 799.9992, 766.6659, 799.9992, 799.9992, 799.9992,
        799.9992, 799.9992, 799.9992, 833.3325, 799.9992, 766.6659,
        799.9992, 799.9992, 766.6659, 799.9992, 766.6659, 799.9992,
        766.6659, 766.6659, 766.6659, 766.6659, 766.6659, 766.6659,
        766.6659, 766.6659, 766.6659, 766.6659, 733.3326, 733.3326,
        733.3326, 733.3326, 733.3326, 733.3326, 733.3326, 733.3326,
        733.3326, 733.3326, 733.3326, 766.6659, 733.3326, 733.3326,
        733.3326, 733.3326, 733.3326, 799.9992, 766.6659, 766.6659,
        766.6659, 766.6659, 733.3326, 766.6659, 766.6659, 766.6659,
        766.6659, 733.3326, 733.3326, 733.3326, 733.3326, 699.9993,
        699.9993, 699.9993, 699.9993, 699.9993, 666.666, 666.666,
        699.9993, 699.9993,
    ]

    private static let longExpected: [String: Double] = [
        "sdnn": 35.36055190357021,
        "median_rr": 733.3326,
        "cv_rr": 0.04701312646706598,
        "rmssd": 21.900122093776147,
        "pnn50": 1.4388489208633095,
        "pnn20": 38.84892086330935,
        "mean_hr": 79.94853118673397,
        "std_hr": 3.7849216975008186,
        "min_hr": 72.000072000072,
        "max_hr": 90.00009000009,
        "hr_range": 18.000018000018002,
        "lf_power": 58.318725509807855,
        "hf_power": 85.80697497038071,
        "lf_hf_ratio": 0.679650174475194,
        "total_power": 144.12570048018856,
        "lf_norm": 40.46379328288109,
        "sd1": 15.538003781388825,
        "sd2": 47.53217542191513,
        "sd_ratio": 3.0590915081928616,
    ]

    // Encoding is what the API actually receives, so this checks the wire names the
    // model indexes by, not just the arithmetic.
    private func computedFeatures(for rr: [Double] = HRVFeaturesTests.rrMilliseconds) throws -> [String: Double] {
        let request = try XCTUnwrap(HRVFeatures.compute(rrMilliseconds: rr))
        let encoded = try JSONEncoder().encode(request)
        return try JSONDecoder().decode([String: Double].self, from: encoded)
    }

    private func assertMatchesPipeline(_ rr: [Double], _ golden: [String: Double]) throws {
        let actual = try computedFeatures(for: rr)
        for name in golden.keys.sorted() {
            let expected = try XCTUnwrap(golden[name])
            let value = try XCTUnwrap(actual[name], "\(name) missing from the request")
            XCTAssertEqual(value, expected, accuracy: abs(expected) * 1e-9 + 1e-12, name)
        }
    }

    func testFeaturesMatchTrainingPipeline() throws {
        try assertMatchesPipeline(Self.rrMilliseconds, Self.expected)
    }

    // Exercises Welch's segment averaging, which a 60-second window never reaches.
    func testLongerWindowFeaturesMatchTrainingPipeline() throws {
        try assertMatchesPipeline(Self.longRRMilliseconds, Self.longExpected)
    }

    func testRequestCarriesExactlyTheModelsFeatures() throws {
        XCTAssertEqual(Set(try computedFeatures().keys), Set(Self.expected.keys))
    }

    func testTooFewSurvivingBeatsYieldsNoFeatures() {
        XCTAssertNil(HRVFeatures.compute(rrMilliseconds: Array(Self.rrMilliseconds.prefix(20))))
    }

    // The whole extraction runs on the main thread the moment a measurement ends.
    func testExtractionIsFastEnoughToRunOnTheMainThread() {
        measure { _ = HRVFeatures.compute(rrMilliseconds: Self.longRRMilliseconds) }
    }
}
