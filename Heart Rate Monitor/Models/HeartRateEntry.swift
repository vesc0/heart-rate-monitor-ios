//
//  HeartrateEntry.swift
//  Heart Rate Monitor
//
//  Created by Vesco on 9/2/25.
//

import Foundation

enum MeasurementState: String, CaseIterable, Codable, Identifiable {
    case resting
    case activity
    case recovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .resting:
            return "Resting"
        case .activity:
            return "Activity"
        case .recovery:
            return "Recovery"
        }
    }

    var contextDescription: String {
        switch self {
        case .resting:
            return "at rest"
        case .activity:
            return "during activity"
        case .recovery:
            return "during recovery"
        }
    }

    var normalRange: ClosedRange<Int> {
        switch self {
        case .resting:
            return 60...100
        case .activity:
            return 90...160
        case .recovery:
            return 60...120
        }
    }

    func assessment(for bpm: Int) -> HeartRateRangeAssessment {
        let low = normalRange.lowerBound
        let high = normalRange.upperBound

        if normalRange.contains(bpm) {
            return HeartRateRangeAssessment(
                isNormal: true,
                title: "Normal for \(displayName)",
                detail: "Expected range \(low)-\(high) BPM \(contextDescription)."
            )
        }

        let relation = bpm < low ? "Below" : "Above"
        return HeartRateRangeAssessment(
            isNormal: false,
            title: "\(relation) normal for \(displayName)",
            detail: "Expected range \(low)-\(high) BPM \(contextDescription)."
        )
    }
}

struct HeartRateRangeAssessment {
    let isNormal: Bool
    let title: String
    let detail: String
}

struct HeartRateEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let bpm: Int
    let date: Date
    let stressLevel: String?
    let activityState: MeasurementState?
    let stressExplanation: String?

    // convenience initializer for new entries
    init(
        bpm: Int,
        date: Date,
        id: UUID = UUID(),
        stressLevel: String? = nil,
        activityState: MeasurementState? = nil,
        stressExplanation: String? = nil
    ) {
        self.id = id
        self.bpm = bpm
        self.date = date
        self.stressLevel = stressLevel
        self.activityState = activityState
        self.stressExplanation = stressExplanation
    }

    private enum CodingKeys: String, CodingKey { case id, bpm, date, stressLevel, activityState, stressExplanation }

    // custom decode to keep compatibility if older entries lack stressLevel/activityState
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try c.decode(Int.self, forKey: .bpm)
        date = try c.decode(Date.self, forKey: .date)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        stressLevel = try? c.decode(String.self, forKey: .stressLevel)
        if let rawState = try? c.decode(String.self, forKey: .activityState) {
            activityState = MeasurementState(rawValue: rawState.lowercased())
        } else {
            activityState = nil
        }
        stressExplanation = try? c.decode(String.self, forKey: .stressExplanation)
    }
}
