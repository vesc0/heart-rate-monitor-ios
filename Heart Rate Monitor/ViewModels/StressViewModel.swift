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
        guard let features = HRVFeatures.compute(rrMilliseconds: intervals.map { $0 * 1000.0 }) else {
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
}
