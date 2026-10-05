//
//  HealthKitService.swift
//  Heart Rate Monitor
//

import Foundation
import HealthKit

final class HealthKitService {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    private var didRequestAuthorization = false

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var canWriteHeartRate: Bool {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return false
        }
        return healthStore.authorizationStatus(for: heartRateType) == .sharingAuthorized
    }

    func ensureWriteAuthorization() async -> Bool {
        guard isAvailable,
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return false
        }

        if canWriteHeartRate {
            didRequestAuthorization = true
            return true
        }

        let granted = await requestAuthorization(writeTypes: [heartRateType])
        didRequestAuthorization = granted
        return granted
    }

    func saveHeartRate(bpm: Int, at date: Date, id: UUID) async -> Bool {
        guard isAvailable,
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return false
        }

        if !didRequestAuthorization && !canWriteHeartRate {
            let granted = await ensureWriteAuthorization()
            guard granted else { return false }
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let quantity = HKQuantity(unit: unit, doubleValue: Double(bpm))
        // The sync identifier makes re-exporting an entry replace its sample instead of duplicating it.
        let sample = HKQuantitySample(
            type: heartRateType, quantity: quantity, start: date, end: date,
            metadata: [HKMetadataKeySyncIdentifier: id.uuidString, HKMetadataKeySyncVersion: 1]
        )

        return await withCheckedContinuation { continuation in
            healthStore.save(sample) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    private func requestAuthorization(writeTypes: Set<HKSampleType>) async -> Bool {
        await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: writeTypes, read: nil) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
