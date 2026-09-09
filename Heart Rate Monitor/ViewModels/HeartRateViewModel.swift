//
//  HeartRateViewModel.swift
//  Heart Rate Monitor
//
//  Created by Vesco on 9/2/25.
//

import Foundation
import SwiftUI

class HeartRateViewModel: ObservableObject {
    // Phase / UI
    @Published var phase: SessionPhase = .idle
    @Published var currentBPM: Int? = nil
    @Published var heartScale: CGFloat = 1.0
    @Published var secondsLeft: Int = 0
    @Published var log: [HeartRateEntry] = []
    @Published var canShowBPM: Bool = false
    @Published var isAppleHealthSyncEnabled: Bool = true

    // Taps & computation
    private var tapTimes: [Date] = []
    // Exposed read-only flag for the View
    var hasTapped: Bool {
        !tapTimes.isEmpty
    }
    
    private var validIntervals: [TimeInterval] = []
    private let smoothingWindow = 5

    // Durations
    private let measureDuration: TimeInterval = 12
    private let previewDuration: TimeInterval = 10
    private let minValidInterval: TimeInterval = 0.27
    private let maxValidInterval: TimeInterval = 1.50
    private let bpmRevealAfter: TimeInterval = 4.0

    // Timers
    private var phaseTimer: Timer?
    private var countdownTimer: Timer?
    private var autoBeatTimer: Timer?
    private var bpmRevealTimer: Timer?

    // Persistence
    private let saveKey = "HeartRateLog"
    private let pendingCreatesKey = "HeartRateLog.pendingCreates"
    private let pendingDeletesKey = "HeartRateLog.pendingDeletes"
    private let healthSyncEnabledKey = "AppleHealthSyncEnabled"

    // Outbox: work the server has not acknowledged yet, retried on every refresh.
    private var pendingCreates: Set<UUID> = []
    private var pendingDeletes: Set<UUID> = []
    private var isFlushing = false
    private let api = APIService.shared
    private let healthKit = HealthKitService.shared

    init() { loadData() }

    // MARK: - Session
    func startSession() {
        invalidateAllTimers()
        resetInMemoryOnly()
        phase = .measuring
        // Timer starts on first tap
    }

    func recordTap() {
        guard phase == .measuring else { return }
        let now = Date()
        
        // If this is the first tap in measuring, start the 12s measurement countdown
        if phase == .measuring && tapTimes.isEmpty {
            startPhase(duration: measureDuration)
            scheduleBPMReveal(after: bpmRevealAfter)
        }
        
        tapTimes.append(now)

        // Compute interval if not first tap
        if let last = tapTimes.dropLast().last {
            let interval = now.timeIntervalSince(last)
            guard interval >= minValidInterval, interval <= maxValidInterval else { return }

            validIntervals.append(interval)
            updateLiveBPM()

            // Pulse heart on user tap only
            pulseHeart()
        }
    }

    private func finishMeasuring() {
        // Manual mode: end immediately at 12s
        updateLiveBPM()
        endSession()
    }

    private func endSession() {
        let finalBPM = computeAverageBPM(from: validIntervals)
        currentBPM = finalBPM

        phase = .finished
        invalidateAllTimers()
    }

    func startNewSession() {
        invalidateAllTimers()
        resetInMemoryOnly()
        phase = .idle
    }
    
    func stopSession() {
        invalidateAllTimers()
        resetInMemoryOnly()
        phase = .idle
    }

    // MARK: - Phase timers
    private func startPhase(duration: TimeInterval) {
        secondsLeft = Int(duration)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self = self else { return }
            self.secondsLeft -= 1
            if self.secondsLeft <= 0 { t.invalidate() }
        }

        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.phase == .measuring {
                self.finishMeasuring()
            }
        }
    }
    
    private func scheduleBPMReveal(after delay: TimeInterval) {
        canShowBPM = false
        bpmRevealTimer?.invalidate()
        bpmRevealTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.canShowBPM = true
        }
    }

    // MARK: - Heart beat (manual: only on tap)
    private func startAutoBeat() {
        // Not used in manual mode anymore
        autoBeatTimer?.invalidate()
    }

    private func pulseHeart() {
        withAnimation(.easeInOut(duration: 0.12)) {
            self.heartScale = 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.12)) {
                self.heartScale = 1.0
            }
        }
    }

    // MARK: - BPM math
    private func updateLiveBPM() {
        let bpm = computeAverageBPM(from: Array(validIntervals.suffix(smoothingWindow)))
        currentBPM = bpm
        // No autoBeat in manual
    }

    private func computeAverageBPM(from intervals: [TimeInterval]) -> Int? {
        guard !intervals.isEmpty else { return nil }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        guard avg > 0 else { return nil }
        return Int(60.0 / avg)
    }

    // MARK: - Helpers
    private func resetInMemoryOnly() {
        currentBPM = nil
        heartScale = 1.0
        secondsLeft = 0
        tapTimes.removeAll()
        validIntervals.removeAll()
        canShowBPM = false
    }

    private func invalidateAllTimers() {
        phaseTimer?.invalidate(); phaseTimer = nil
        countdownTimer?.invalidate(); countdownTimer = nil
        autoBeatTimer?.invalidate(); autoBeatTimer = nil
        bpmRevealTimer?.invalidate(); bpmRevealTimer = nil
    }

    // MARK: - Persistence (local cache + remote API)

    // Insert a new entry locally and sync to the server.
    func addEntry(_ entry: HeartRateEntry) {
        log.insert(entry, at: 0)
        pendingCreates.insert(entry.id)
        saveLocal()
        flush()
        if isAppleHealthSyncEnabled {
            Task {
                _ = await healthKit.saveHeartRate(bpm: entry.bpm, at: entry.date)
            }
        }
    }

    func setAppleHealthSyncEnabled(_ enabled: Bool) {
        isAppleHealthSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: healthSyncEnabledKey)
    }

    struct AppleHealthExportResult {
        let exportedCount: Int
        let failedCount: Int
        let totalCount: Int
    }

    func exportHistoryToAppleHealth() async -> AppleHealthExportResult {
        let snapshot = log
        guard !snapshot.isEmpty else {
            return AppleHealthExportResult(exportedCount: 0, failedCount: 0, totalCount: 0)
        }

        let authorized = await healthKit.ensureWriteAuthorization()
        guard authorized else {
            return AppleHealthExportResult(exportedCount: 0, failedCount: snapshot.count, totalCount: snapshot.count)
        }

        var exported = 0
        var failed = 0
        for entry in snapshot {
            let ok = await healthKit.saveHeartRate(bpm: entry.bpm, at: entry.date)
            if ok { exported += 1 } else { failed += 1 }
        }

        return AppleHealthExportResult(exportedCount: exported, failedCount: failed, totalCount: snapshot.count)
    }

    // Delete entries by their IDs (locally + remote).
    func deleteEntries(ids: Set<UUID>) {
        log.removeAll { ids.contains($0.id) }
        // Entries the server never received just disappear; there is nothing to delete.
        pendingDeletes.formUnion(ids.subtracting(pendingCreates))
        pendingCreates.subtract(ids)
        saveLocal()
        flush()
    }

    // Update a single existing entry locally and sync the latest value to the server.
    func updateEntry(_ entry: HeartRateEntry) {
        guard let idx = log.firstIndex(where: { $0.id == entry.id }) else { return }
        log[idx] = entry
        pendingCreates.insert(entry.id)
        saveLocal()
        flush()
    }

    // Persist the current log and outbox to UserDefaults (local cache only).
    func saveLocal() {
        let defaults = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(log) {
            defaults.set(encoded, forKey: saveKey)
        }
        defaults.set(pendingCreates.map(\.uuidString), forKey: pendingCreatesKey)
        defaults.set(pendingDeletes.map(\.uuidString), forKey: pendingDeletesKey)
    }

    // Legacy alias kept for callers that only need a local write (e.g. demo seed).
    func saveData() { saveLocal() }

    // Clear all local data (used on sign-out to prevent data leakage between accounts).
    func clearForLogout() {
        log.removeAll()
        pendingCreates.removeAll()
        pendingDeletes.removeAll()
        [saveKey, pendingCreatesKey, pendingDeletesKey].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    // Drain the outbox, then replace the cache with the server's view of the data.
    func refreshFromServer() {
        guard api.isAuthenticated else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.flushOutbox()
            do {
                var remote: [HeartRateEntryResponse] = []
                var offset = 0
                let pageSize = 500

                while true {
                    let page = try await api.fetchHeartRateEntries(limit: pageSize, offset: offset)
                    remote.append(contentsOf: page)

                    if page.count < pageSize {
                        break
                    }
                    offset += pageSize
                }

                var merged: [UUID: HeartRateEntry] = [:]
                for item in remote {
                    guard let id = UUID(uuidString: item.id), !self.pendingDeletes.contains(id) else { continue }
                    merged[id] = HeartRateEntry(
                        bpm: item.bpm,
                        date: item.recordedAt,
                        id: id,
                        stressLevel: item.stressLevel,
                        activityState: item.activityState,
                        stressExplanation: item.stressExplanation
                    )
                }
                // Anything still queued has not reached the server, so keep the local copy.
                for entry in self.log where self.pendingCreates.contains(entry.id) {
                    merged[entry.id] = entry
                }

                self.log = merged.values.sorted { $0.date > $1.date }
                self.saveLocal()
            } catch {
                // Keep local data on error; server refresh is best-effort
            }
        }
    }

    private func loadData() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: healthSyncEnabledKey) == nil {
            isAppleHealthSyncEnabled = true
        } else {
            isAppleHealthSyncEnabled = defaults.bool(forKey: healthSyncEnabledKey)
        }

        // Load cached data from UserDefaults first (instant)
        if let data = defaults.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([HeartRateEntry].self, from: data) {
            log = decoded
        }
        pendingCreates = Self.storedIDs(defaults.stringArray(forKey: pendingCreatesKey))
        pendingDeletes = Self.storedIDs(defaults.stringArray(forKey: pendingDeletesKey))

        // Then try to refresh from the server in the background
        refreshFromServer()
    }

    private static func storedIDs(_ raw: [String]?) -> Set<UUID> {
        Set((raw ?? []).compactMap(UUID.init(uuidString:)))
    }

    // MARK: - Outbox

    private func flush() {
        Task { @MainActor [weak self] in await self?.flushOutbox() }
    }

    // Retries queued work. Anything that fails stays queued for the next attempt;
    // anything the server rejects outright is dropped so it cannot block the queue.
    @MainActor
    private func flushOutbox() async {
        guard api.isAuthenticated, !isFlushing else { return }
        guard !pendingCreates.isEmpty || !pendingDeletes.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        if !pendingDeletes.isEmpty {
            let ids = pendingDeletes
            do {
                try await api.deleteHeartRateEntries(ids: ids.map(\.uuidString))
                pendingDeletes.subtract(ids)
            } catch {
                if Self.isRejected(error) { pendingDeletes.subtract(ids) }
            }
        }

        for id in pendingCreates {
            guard let entry = log.first(where: { $0.id == id }) else {
                pendingCreates.remove(id)
                continue
            }
            do {
                try await api.createHeartRateEntry(entry)
                pendingCreates.remove(id)
            } catch {
                if Self.isRejected(error) { pendingCreates.remove(id) }
            }
        }

        saveLocal()
    }

    private static func isRejected(_ error: Error) -> Bool {
        guard case .serverError(let code, _)? = error as? APIError else { return false }
        return (400..<500).contains(code)
    }
}
