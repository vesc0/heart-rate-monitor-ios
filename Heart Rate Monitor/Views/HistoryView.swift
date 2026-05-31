//
//  HistoryView.swift
//  Heart Rate Monitor
//
//  Created by Vesco on 9/2/25.
//

import SwiftUI
import Charts

struct HistoryView: View {
    @ObservedObject var vm: HeartRateViewModel
    @State private var selectedEntries = Set<HeartRateEntry.ID>()
    @State private var isSelectionMode = false
    @State private var metricMode: HistoryMetric = .heartRate
    @State private var visibleCount: Int = 20
    @State private var detailedMeasurement: HeartRateEntry? = nil

    @State private var monthOffset: Int = 0   // 0 = current month, -1 = previous month
    @State private var selectedDay: Date? = nil

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }
    private var todayStart: Date { calendar.startOfDay(for: Date()) }

    private var shouldSeed: Bool {
        vm.log.isEmpty
    }

    private func seedSampleDataIfNeeded() {
        guard shouldSeed else { return }
        var entries: [HeartRateEntry] = []

        let daysBack = 135
        for d in 0..<daysBack {
            guard let dayDate = calendar.date(byAdding: .day, value: -d, to: todayStart) else { continue }
            let count = Int.random(in: 1...3)
            let baseline = 68 + Int(6 * sin(Double(d) / 9.0))
            for i in 0..<count {
                let bpm = max(45, min(160, baseline + Int.random(in: -12...14)))
                let hour = [9, 14, 20].randomElement() ?? 12
                let minute = Int.random(in: 0..<60)
                var comps = calendar.dateComponents([.year, .month, .day], from: dayDate)
                comps.hour = hour + i
                comps.minute = minute
                let ts = calendar.date(from: comps) ?? dayDate

                // Include stress demo entries so Stress monthly mode has data too.
                let stress: String? = Bool.random() ? String(format: "%d%%", Int.random(in: 18...92)) : nil
                let state = MeasurementState.allCases.randomElement()
                entries.append(HeartRateEntry(bpm: bpm, date: ts, stressLevel: stress, activityState: state))
            }
        }
        entries.sort { $0.date > $1.date }
        vm.log = entries
        vm.saveData()
    }

    private var heartRateDailyRangesAll: [DailyMetricRange] {
        let grouped = Dictionary(grouping: vm.log) { entry in
            calendar.startOfDay(for: entry.date)
        }
        .map { (dayStart, entries) -> DailyMetricRange in
            let values = entries.map(\.bpm)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 0
            let avgValue: Int = {
                guard !values.isEmpty else { return 0 }
                return values.reduce(0, +) / values.count
            }()
            return DailyMetricRange(day: dayStart, min: minValue, max: maxValue, avg: avgValue)
        }
        .sorted { $0.day < $1.day }
        return grouped
    }

    private var stressDailyRangesAll: [DailyMetricRange] {
        let stressEntries = vm.log.compactMap { entry -> (Date, Int)? in
            guard let stress = entry.stressLevel, let pct = stressPercentage(from: stress) else { return nil }
            return (entry.date, pct)
        }

        let grouped = Dictionary(grouping: stressEntries) { pair in
            calendar.startOfDay(for: pair.0)
        }
        .map { (dayStart, entries) -> DailyMetricRange in
            let values = entries.map { $0.1 }
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 0
            let avgValue: Int = {
                guard !values.isEmpty else { return 0 }
                return values.reduce(0, +) / values.count
            }()
            return DailyMetricRange(day: dayStart, min: minValue, max: maxValue, avg: avgValue)
        }
        .sorted { $0.day < $1.day }
        return grouped
    }

    private var currentMonthStart: Date {
        let comps = calendar.dateComponents([.year, .month], from: todayStart)
        let startOfCurrent = calendar.date(from: comps) ?? todayStart
        return calendar.date(byAdding: .month, value: monthOffset, to: startOfCurrent) ?? startOfCurrent
    }

    private var currentMonthRange: (start: Date, end: Date) {
        let start = currentMonthStart
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return (start, end)
    }

    private var monthDays: [Date] {
        let (start, end) = currentMonthRange
        var days: [Date] = []
        var cur = start
        while cur <= end {
            days.append(cur)
            cur = calendar.date(byAdding: .day, value: 1, to: cur) ?? cur.addingTimeInterval(86400)
        }
        return days
    }

    private var monthlyTickDays: [Date] {
        let (start, end) = currentMonthRange
        var ticks: [Date] = []
        ticks.append(start)
        if let d10 = calendar.date(byAdding: .day, value: 9, to: start) { ticks.append(d10) }
        if let d20 = calendar.date(byAdding: .day, value: 19, to: start) { ticks.append(d20) }
        ticks.append(end)
        return ticks
    }

    private var dailyRangesForCurrentMonth: [DailyMetricRange] {
        let source = metricMode == .heartRate ? heartRateDailyRangesAll : stressDailyRangesAll
        let dict = Dictionary(uniqueKeysWithValues: source.map { ($0.day, $0) })
        return monthDays.compactMap { dict[$0] }
    }

    private var hasChartDataForCurrentPeriod: Bool {
        dailyRangesForCurrentMonth.contains { $0.min != 0 || $0.max != 0 }
    }

    private var monthStats: PeriodStats? {
        aggregateStats(for: dailyRangesForCurrentMonth)
    }

    private func aggregateStats(for days: [DailyMetricRange]) -> PeriodStats? {
        guard !days.isEmpty else { return nil }
        let dayMins = days.map(\.min).filter { $0 > 0 }
        let dayMaxs = days.map(\.max).filter { $0 > 0 }
        let dayAvgs = days.map(\.avg).filter { $0 > 0 }
        guard !dayMins.isEmpty, !dayMaxs.isEmpty, !dayAvgs.isEmpty else { return nil }
        let minVal = dayMins.min() ?? 0
        let maxVal = dayMaxs.max() ?? 0
        let avgVal = dayAvgs.reduce(0, +) / dayAvgs.count
        return PeriodStats(min: minVal, avg: avgVal, max: maxVal)
    }

    private var displayStats: PeriodStats? {
        if let sel = selectedDay,
           let day = dailyRangesForCurrentMonth.first(where: { calendar.isDate($0.day, inSameDayAs: sel) }) {
            return PeriodStats(min: day.min, avg: day.avg, max: day.max)
        }
        return monthStats
    }

    private var filteredMeasurements: [HeartRateEntry] {
        let (start, end) = currentMonthRange
        let base = vm.log.filter { $0.date >= start && $0.date <= end.addingTimeInterval(24*60*60 - 1) }
        let metricFiltered: [HeartRateEntry] = {
            switch metricMode {
            case .heartRate:
                return base
            case .stress:
                return base.filter { $0.stressLevel != nil }
            }
        }()

        if let sel = selectedDay {
            let startSel = sel
            let endSel = sel.addingTimeInterval(24 * 60 * 60 - 1)
            return metricFiltered.filter { $0.date >= startSel && $0.date <= endSel }
        }

        return metricFiltered
    }

    private var sortedFilteredMeasurements: [HeartRateEntry] {
        filteredMeasurements.sorted { $0.date > $1.date }
    }

    private var pagedLog: [HeartRateEntry] {
        let end = min(visibleCount, filteredMeasurements.count)
        return Array(sortedFilteredMeasurements.prefix(end))
    }

    private var hasMore: Bool {
        visibleCount < filteredMeasurements.count
    }

    private let pageSize = 20

    private var periodTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "LLLL yyyy"
        return fmt.string(from: currentMonthStart)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                Group {
                    if vm.log.isEmpty {
                        GeometryReader { proxy in
                            ScrollView {
                                VStack(spacing: 8) {
                                    Text("No Records")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("Records will appear here after you complete a measurement.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)

                                    Button("Load Demo Data") {
                                        seedSampleDataIfNeeded()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .padding(.top, 8)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: proxy.size.height, alignment: .center)
                                .padding()
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .scrollIndicators(.hidden)
                        }
                    } else {
                        List {
                        Section {
                            Picker("Metric", selection: $metricMode) {
                                Text("Heart Rate").tag(HistoryMetric.heartRate)
                                Text("Stress").tag(HistoryMetric.stress)
                            }
                            .pickerStyle(.segmented)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                            HStack {
                                Button {
                                    withAnimation(.easeInOut) {
                                        monthOffset -= 1
                                        selectedDay = nil
                                        updateVisibleCountForFilter(resetToFirstPage: true)
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Text(periodTitle)
                                    .font(.headline)

                                Spacer()

                                Button {
                                    withAnimation(.easeInOut) {
                                        monthOffset = min(0, monthOffset + 1)
                                        selectedDay = nil
                                        updateVisibleCountForFilter(resetToFirstPage: true)
                                    }
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .buttonStyle(.plain)
                                .disabled(monthOffset == 0)
                                .opacity(monthOffset == 0 ? 0.4 : 1)
                            }
                            .padding(.top, 4)
                            .listRowSeparator(.hidden)

                            if hasChartDataForCurrentPeriod {
                                chartView()
                                    .frame(height: 240)
                                    .padding(.bottom, 6)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                    .listRowSeparator(.hidden)
                            } else {
                                Text("No data in this period.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 24)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                    .listRowSeparator(.hidden)
                            }
                        } footer: {
                            if let stats = displayStats {
                                VStack(spacing: 10) {
                                    HStack(spacing: 18) {
                                        statPillLarge(title: "Min", value: stats.min)
                                        statPillLarge(title: "Avg", value: stats.avg)
                                        statPillLarge(title: "Max", value: stats.max)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 10)
                                .padding(.bottom, 14)
                            }
                        }

                        if !pagedLog.isEmpty {
                            Section {
                                ForEach(pagedLog) { entry in
                                    HStack(spacing: 12) {
                                        if isSelectionMode {
                                            Image(systemName: selectedEntries.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedEntries.contains(entry.id) ? .accentColor : .gray)
                                        }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                                            Image(systemName: "heart.fill")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.red)
                                            Text("\(entry.bpm)")
                                                .font(.title2.weight(.black))
                                                .foregroundStyle(heartRateValueColor(for: entry.bpm))
                                            Text("BPM")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        if let stress = entry.stressLevel {
                                            Text(stressDisplayText(for: stress))
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(stressColor(for: stress))
                                        }
                                    }

                                    Spacer(minLength: 2)

                                    if let state = entry.activityState {
                                        HStack(spacing: 3) {
                                            Image(systemName: activityStateIcon(for: state))
                                            Text(state.displayName)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                        }
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(activityStateColor(for: state))
                                    }

                                    Spacer(minLength: 2)

                                    VStack(alignment: .trailing, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "calendar")
                                                .foregroundStyle(.secondary)
                                            Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                                        }
                                        .font(.caption)

                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .foregroundStyle(.secondary)
                                            Text(entry.date, style: .time)
                                        }
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 84)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(heartRateBackgroundColor(for: entry.bpm))
                                )
                                .listRowBackground(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelectionMode {
                                        if selectedEntries.contains(entry.id) {
                                            selectedEntries.remove(entry.id)
                                        } else {
                                            selectedEntries.insert(entry.id)
                                        }
                                    } else {
                                        detailedMeasurement = entry
                                    }
                                }
                                .onAppear {
                                    loadMoreIfNeeded(currentItem: entry)
                                }
                            }
                            .onDelete { offsets in
                                let toDelete = Set(offsets.map { pagedLog[$0].id })
                                vm.deleteEntries(ids: toDelete)
                                updateVisibleCountForFilter()
                            }
                            .listRowSeparator(.hidden)
                        } header: {
                            HStack {
                                Text(measurementsHeaderTitle)
                                Spacer()
                                if isSelectionMode {
                                    Button("Cancel") {
                                        isSelectionMode = false
                                        selectedEntries.removeAll()
                                    }
                                    .buttonStyle(.plain)

                                    Button("Select All") {
                                        let ids = filteredMeasurements.map(\.id)
                                        selectedEntries = Set(ids)
                                    }
                                    .buttonStyle(.plain)

                                    Button("Delete") {
                                        vm.deleteEntries(ids: selectedEntries)
                                        isSelectionMode = false
                                        selectedEntries.removeAll()
                                        updateVisibleCountForFilter()
                                    }
                                    .foregroundColor(.red)
                                    .disabled(selectedEntries.isEmpty)
                                } else {
                                    if !filteredMeasurements.isEmpty {
                                        Button("Select") {
                                            isSelectionMode = true
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                    }
                    .listStyle(.grouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $detailedMeasurement) { entry in
            MeasurementDetailView(entry: entry)
        }
        .onChange(of: vm.log) { _, _ in
            updateVisibleCountForFilter()
            selectedEntries = selectedEntries.filter { id in vm.log.contains(where: { $0.id == id }) }
        }
        .onChange(of: metricMode) { _, _ in
            monthOffset = 0
            selectedDay = nil
            updateVisibleCountForFilter(resetToFirstPage: true)
        }
    }
}

}

private enum HistoryMetric: String, CaseIterable, Identifiable {
    case heartRate = "Heart Rate"
    case stress = "Stress"
    var id: String { rawValue }
}

private struct DailyMetricRange: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    let min: Int
    let max: Int
    let avg: Int
}

private struct PeriodStats {
    let min: Int
    let avg: Int
    let max: Int
}

private extension HistoryView {
    func stressPercentage(from stress: String) -> Int? {
        Int(stress.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func isSelected(_ day: DailyMetricRange) -> Bool {
        guard let s = selectedDay else { return false }
        return calendar.isDate(s, inSameDayAs: day.day)
    }

    func toggleSelection(for date: Date) {
        if let s = selectedDay, calendar.isDate(s, inSameDayAs: date) {
            selectedDay = nil
        } else {
            selectedDay = date
        }
        updateVisibleCountForFilter(resetToFirstPage: true)
    }

    func updateVisibleCountForFilter(resetToFirstPage: Bool = false) {
        let total = sortedFilteredMeasurements.count

        guard total > 0 else {
            visibleCount = 0
            return
        }

        if resetToFirstPage || visibleCount == 0 {
            visibleCount = min(pageSize, total)
            return
        }

        visibleCount = min(max(pageSize, visibleCount), total)
    }

    func loadMoreIfNeeded(currentItem item: HeartRateEntry) {
        guard hasMore else { return }
        guard let index = pagedLog.firstIndex(where: { $0.id == item.id }) else { return }

        let thresholdIndex = max(0, pagedLog.count - 4)
        guard index >= thresholdIndex else { return }

        visibleCount = min(visibleCount + pageSize, sortedFilteredMeasurements.count)
    }

    func dayLabel(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE d"
        return df.string(from: date)
    }

    func stressColor(for stress: String) -> Color {
        if let pct = stressPercentage(from: stress) {
            if pct >= 70 { return .red }
            if pct >= 40 { return .orange }
            return .green
        }

        let normalized = stress.lowercased()
        if normalized.contains("high") || normalized.contains("stressed") { return .red }
        if normalized.contains("medium") || normalized.contains("moderate") { return .orange }
        return .green
    }

    func stressDisplayText(for stress: String) -> String {
        if let pct = stressPercentage(from: stress) {
            return "\(pct)% stressed"
        }
        return stress
    }

    func activityStateIcon(for state: MeasurementState) -> String {
        switch state {
        case .resting: return "bed.double.fill"
        case .activity: return "figure.run"
        case .recovery: return "heart.circle.fill"
        }
    }

    func activityStateColor(for state: MeasurementState) -> Color {
        switch state {
        case .resting:
            return .blue
        case .activity:
            return .orange
        case .recovery:
            return .mint
        }
    }

    func heartRateBandColor(for bpm: Int) -> Color {
        switch bpm {
        case 60...100:
            return .green
        case 50...59, 101...110:
            return .yellow
        default:
            return .red
        }
    }

    func heartRateValueColor(for bpm: Int) -> Color {
        heartRateBandColor(for: bpm)
    }

    func heartRateBackgroundColor(for bpm: Int) -> Color {
        Color(.secondarySystemGroupedBackground)
    }

    var measurementsHeaderTitle: String {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        if let s = selectedDay {
            let dayFmt = DateFormatter()
            dayFmt.dateStyle = .medium
            return "Measurements – \(dayFmt.string(from: s))"
        }
        return "Measurements – \(df.string(from: currentMonthStart))"
    }

    var valueUnitLabel: String {
        metricMode == .heartRate ? "BPM" : "%"
    }

    var chartXDomain: ClosedRange<Date> {
        let (start, end) = currentMonthRange
        let left = calendar.date(byAdding: .hour, value: -12, to: start) ?? start
        let rightPad = calendar.date(byAdding: .hour, value: 60, to: end) ?? end
        return left...rightPad
    }

    @ChartContentBuilder
    func chartBackgroundZones(_ yDomain: ClosedRange<Double>) -> some ChartContent {
        switch metricMode {
        case .heartRate:
            let low = yDomain.lowerBound
            let high = yDomain.upperBound

            let lowRedStart = low
            let lowRedEnd = min(50.0, high)
            if lowRedEnd > lowRedStart {
                RectangleMark(
                    xStart: .value("Start", chartXDomain.lowerBound),
                    xEnd: .value("End", chartXDomain.upperBound),
                    yStart: .value("Low red", lowRedStart),
                    yEnd: .value("Low red top", lowRedEnd)
                )
                .foregroundStyle(Color.red.opacity(0.14))
            }

            let lowYellowStart = max(50.0, low)
            let lowYellowEnd = min(60.0, high)
            if lowYellowEnd > lowYellowStart {
                RectangleMark(
                    xStart: .value("Start", chartXDomain.lowerBound),
                    xEnd: .value("End", chartXDomain.upperBound),
                    yStart: .value("Low yellow", lowYellowStart),
                    yEnd: .value("Low yellow top", lowYellowEnd)
                )
                .foregroundStyle(Color.yellow.opacity(0.14))
            }

            let greenStart = max(60.0, low)
            let greenEnd = min(100.0, high)
            if greenEnd > greenStart {
                RectangleMark(
                    xStart: .value("Start", chartXDomain.lowerBound),
                    xEnd: .value("End", chartXDomain.upperBound),
                    yStart: .value("Green", greenStart),
                    yEnd: .value("Green top", greenEnd)
                )
                .foregroundStyle(Color.green.opacity(0.14))
            }

            let highYellowStart = max(100.0, low)
            let highYellowEnd = min(110.0, high)
            if highYellowEnd > highYellowStart {
                RectangleMark(
                    xStart: .value("Start", chartXDomain.lowerBound),
                    xEnd: .value("End", chartXDomain.upperBound),
                    yStart: .value("High yellow", highYellowStart),
                    yEnd: .value("High yellow top", highYellowEnd)
                )
                .foregroundStyle(Color.yellow.opacity(0.14))
            }

            let highRedStart = max(110.0, low)
            let highRedEnd = high
            if highRedEnd > highRedStart {
                RectangleMark(
                    xStart: .value("Start", chartXDomain.lowerBound),
                    xEnd: .value("End", chartXDomain.upperBound),
                    yStart: .value("High red", highRedStart),
                    yEnd: .value("High red top", highRedEnd)
                )
                .foregroundStyle(Color.red.opacity(0.14))
            }
        case .stress:
            RectangleMark(
                xStart: .value("Start", chartXDomain.lowerBound),
                xEnd: .value("End", chartXDomain.upperBound),
                yStart: .value("Green", 0),
                yEnd: .value("Green top", 40)
            )
            .foregroundStyle(Color.green.opacity(0.14))

            RectangleMark(
                xStart: .value("Start", chartXDomain.lowerBound),
                xEnd: .value("End", chartXDomain.upperBound),
                yStart: .value("Yellow", 40),
                yEnd: .value("Yellow top", 70)
            )
            .foregroundStyle(Color.yellow.opacity(0.14))

            RectangleMark(
                xStart: .value("Start", chartXDomain.lowerBound),
                xEnd: .value("End", chartXDomain.upperBound),
                yStart: .value("Red", 70),
                yEnd: .value("Red top", 100)
            )
            .foregroundStyle(Color.red.opacity(0.14))
        }
    }

    @ViewBuilder
    func chartView() -> some View {
        let baseData: [DailyMetricRange] = dailyRangesForCurrentMonth
        let chartData: [DailyMetricRange] = baseData.filter { $0.min != 0 || $0.max != 0 }
        let minDataValue = Double(chartData.map(\.min).min() ?? 50)
        let maxDataValue = Double(chartData.map(\.max).max() ?? 100)

        let heartRateLowerDynamic = floor((minDataValue - 6.0) / 5.0) * 5.0
        let heartRateUpperDynamic = ceil((maxDataValue + 8.0) / 5.0) * 5.0
        let heartRateLower = min(40.0, heartRateLowerDynamic)
        let heartRateUpper = max(120.0, heartRateUpperDynamic)
        let heartRateDomain: ClosedRange<Double> = heartRateLower...heartRateUpper
        let stressDomain: ClosedRange<Double> = 0...100

        Chart {
            chartBackgroundZones(metricMode == .heartRate ? heartRateDomain : stressDomain)

            ForEach(chartData) { day in
                ChartBar(
                    day: day,
                    isSelected: isSelected(day),
                    hasSelection: selectedDay != nil,
                    labelProvider: { dayLabel(for: day.day) }
                )
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: metricMode == .heartRate ? heartRateDomain : stressDomain)
        .chartXAxis {
            monthlyXAxis()
        }
        .chartYAxis {
            if metricMode == .stress {
                AxisMarks(position: .trailing, values: [0.0, 40.0, 70.0, 100.0])
            } else {
                AxisMarks(position: .trailing)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { _ in
                Color.clear
                    .allowsHitTesting(false)
                    .background(
                        TapCatcher { location in
                            guard let tappedDate: Date = proxy.value(atX: location.x) else { return }
                            let dayStart = calendar.startOfDay(for: tappedDate)
                            guard let dayData = dailyRangesForCurrentMonth.first(where: { calendar.isDate($0.day, inSameDayAs: dayStart) }) else { return }
                            guard let dayX: CGFloat = proxy.position(forX: dayData.day) else { return }

                            let dx = abs(dayX - location.x)
                            let xHitSlop: CGFloat = 18
                            guard dx <= xHitSlop else { return }

                            guard
                                let yMin: CGFloat = proxy.position(forY: Double(dayData.min)),
                                let yMax: CGFloat = proxy.position(forY: Double(dayData.max))
                            else { return }
                            let yLow = min(yMin, yMax)
                            let yHigh = max(yMin, yMax)
                            let yPadding: CGFloat = 14
                            let yHit = (location.y >= (yLow - yPadding)) && (location.y <= (yHigh + yPadding))
                            guard yHit else { return }

                            toggleSelection(for: dayData.day)
                        }
                    )
            }
        }
    }

    @AxisContentBuilder
    func monthlyXAxis() -> some AxisContent {
        AxisMarks(values: monthlyTickDays) { value in
            AxisGridLine()
            AxisTick()
            if let dateValue: Date = value.as(Date.self) {
                let d = calendar.component(.day, from: dateValue)
                AxisValueLabel("\(d)")
            }
        }
    }

    @ViewBuilder
    func statPillLarge(title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(metricValueColor(for: value))
                    .frame(width: 42, alignment: .trailing)
                Text(valueUnitLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(width: 116)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    func metricValueColor(for value: Int) -> Color {
        switch metricMode {
        case .heartRate:
            return heartRateBandColor(for: value)
        case .stress:
            if value >= 70 { return .red }
            if value >= 40 { return .yellow }
            return .green
        }
    }
}

private struct ChartBar: ChartContent {
    let day: DailyMetricRange
    let isSelected: Bool
    let hasSelection: Bool
    let labelProvider: () -> String

    var body: some ChartContent {
        let width: CGFloat = isSelected ? 18 : 6
        let color: Color = isSelected ? .red : Color.red.opacity(0.85)
        let alpha: Double = hasSelection ? (isSelected ? 1.0 : 0.35) : 1.0

        RuleMark(
            x: .value("Day", day.day),
            yStart: .value("Min", day.min),
            yEnd: .value("Max", day.max)
        )
        .foregroundStyle(color)
        .lineStyle(StrokeStyle(lineWidth: width, lineCap: .round))
        .opacity(alpha)
        .accessibilityLabel(Text("\(labelProvider()): \(day.min)–\(day.max)"))
    }
}

private struct TapCatcher: UIViewRepresentable {
    var onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PassThroughTapView {
        let view = PassThroughTapView()
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PassThroughTapView, context: Context) {
        uiView.onTap = onTap
    }
}

private final class PassThroughTapView: UIView {
    var onTap: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        let point = gr.location(in: self)
        onTap?(point)
    }
}

private struct MeasurementDetailView: View {
    let entry: HeartRateEntry
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.red)
                        
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(entry.bpm)")
                                .font(.system(size: 80, weight: .black, design: .rounded))
                                .foregroundStyle(heartRateValueColor(for: entry.bpm))
                            Text("BPM")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section("Details") {
                    HStack {
                        Label("Date", systemImage: "calendar")
                        Spacer()
                        Text(entry.date, format: .dateTime.month(.wide).day().year())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Time", systemImage: "clock")
                        Spacer()
                        Text(entry.date, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    if let state = entry.activityState {
                        HStack {
                            Label("Activity", systemImage: activityStateIcon(for: state))
                            Spacer()
                            Text(state.displayName)
                                .fontWeight(.semibold)
                                .foregroundStyle(activityStateColor(for: state))
                        }
                    }
                    if let stress = entry.stressLevel {
                        HStack {
                            Label("Stress Level", systemImage: "brain.head.profile")
                            Spacer()
                            Text(stressDisplayText(for: stress))
                                .fontWeight(.medium)
                                .foregroundStyle(stressColor(for: stress))
                        }
                    }
                }
            }
            .navigationTitle("Measurement Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func stressPercentage(from stress: String) -> Int? {
        Int(stress.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func stressColor(for stress: String) -> Color {
        if let pct = stressPercentage(from: stress) {
            if pct >= 70 { return .red }
            if pct >= 40 { return .orange }
            return .green
        }

        let normalized = stress.lowercased()
        if normalized.contains("high") || normalized.contains("stressed") { return .red }
        if normalized.contains("medium") || normalized.contains("moderate") { return .orange }
        return .green
    }

    private func stressDisplayText(for stress: String) -> String {
        if let pct = stressPercentage(from: stress) {
            return "\(pct)% stressed"
        }
        return stress
    }

    private func activityStateIcon(for state: MeasurementState) -> String {
        switch state {
        case .resting: return "bed.double.fill"
        case .activity: return "figure.run"
        case .recovery: return "heart.circle.fill"
        }
    }

    private func activityStateColor(for state: MeasurementState) -> Color {
        switch state {
        case .resting:
            return .blue
        case .activity:
            return .orange
        case .recovery:
            return .mint
        }
    }

    private func heartRateValueColor(for bpm: Int) -> Color {
        switch bpm {
        case 60...100:
            return .green
        case 50...59, 101...110:
            return .yellow
        default:
            return .red
        }
    }
}
