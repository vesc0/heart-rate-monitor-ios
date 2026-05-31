//
//  MeasurementView.swift
//  Heart Rate Monitor
//
//  Created by Vesco on 3/3/26.
//

import SwiftUI
import UIKit

enum MeasurementCategory: String, CaseIterable, Identifiable {
    case heartRate = "Heart Rate"
    case stress = "Stress"
    var id: String { rawValue }
}

enum HeartRateMode: String, CaseIterable, Identifiable {
    case tap = "Tap"
    case camera = "Camera"
    var id: String { rawValue }
}

struct MeasurementView: View {
    @ObservedObject var vm: HeartRateViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var category: MeasurementCategory = .heartRate
    @State private var heartRateMode: HeartRateMode = .camera
    @StateObject private var autoVM = AutoHeartRateViewModel()
    @StateObject private var stressVM = StressViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $category) {
                    ForEach(MeasurementCategory.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Measurement content
                Group {
                    switch category {
                    case .heartRate:
                        VStack(spacing: 0) {
                            TabView(selection: $heartRateMode) {
                                TapContentView(vm: vm) {
                                    stopCameraMeasurementIfNeeded()
                                }
                                    .tag(HeartRateMode.tap)

                                CameraContentView(vm: vm, autoVM: autoVM) {
                                    stopTapMeasurementIfNeeded()
                                }
                                    .tag(HeartRateMode.camera)
                            }
                            .tabViewStyle(.page(indexDisplayMode: .always))
                            .indexViewStyle(.page(backgroundDisplayMode: .always))
                            .onAppear {
                                applyPageIndicatorColors()
                            }
                            .onChange(of: colorScheme) { _, _ in
                                applyPageIndicatorColors()
                            }
                            .onChange(of: heartRateMode) { _, newMode in
                                switch newMode {
                                case .tap:
                                    stopCameraMeasurementIfNeeded()
                                case .camera:
                                    stopTapMeasurementIfNeeded()
                                }
                            }
                        }
                    case .stress:
                        StressContentView(vm: vm, stressVM: stressVM) {
                            stopHeartRateMeasurementsIfNeeded()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Measure")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: category) { _, newCategory in
                switch newCategory {
                case .heartRate:
                    stopStressMeasurementIfNeeded()
                case .stress:
                    stopHeartRateMeasurementsIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    stopAllMeasurementsIfNeeded()
                }
            }
            .onDisappear {
                stopAllMeasurementsIfNeeded()
            }
        }
        .appTopGradientNavigationBar()
    }

    private func applyPageIndicatorColors() {
        if colorScheme == .light {
            UIPageControl.appearance().currentPageIndicatorTintColor = .systemRed
            UIPageControl.appearance().pageIndicatorTintColor = UIColor.systemGray3.withAlphaComponent(0.65)
        } else {
            UIPageControl.appearance().currentPageIndicatorTintColor = .systemRed
            UIPageControl.appearance().pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.35)
        }
    }

    private func stopTapMeasurementIfNeeded() {
        if vm.phase == .measuring {
            vm.stopSession()
        }
    }

    private func stopCameraMeasurementIfNeeded() {
        if autoVM.phase == .measuring {
            autoVM.stopSessionEarly()
        }
    }

    private func stopStressMeasurementIfNeeded() {
        if stressVM.phase == .measuring {
            stressVM.stopSessionEarly()
        }
    }

    private func stopHeartRateMeasurementsIfNeeded() {
        stopTapMeasurementIfNeeded()
        stopCameraMeasurementIfNeeded()
    }

    private func stopAllMeasurementsIfNeeded() {
        stopHeartRateMeasurementsIfNeeded()
        stopStressMeasurementIfNeeded()
    }
}

// MARK: - Stress Measurement Content

private struct StressContentView: View {
    @ObservedObject var vm: HeartRateViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject var stressVM: StressViewModel
    @State private var selectedState: MeasurementState? = nil
    let onStart: () -> Void

    private var totalForCurrentPhase: Int {
        switch stressVM.phase {
        case .measuring: return 60
        default: return 0
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                if stressVM.phase == .idle {
                    VStack(spacing: 16) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.bottom, 4)

                        Text("Stress Measurement")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Place your fingertip over the camera and keep it still for 60 seconds. The app will analyse your heart-rate variability and predict whether you are stressed.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        Button {
                            onStart()
                            stressVM.userAge = auth.age.flatMap { Int($0) }
                            stressVM.userGender = auth.gender
                            stressVM.userHeightCm = auth.heightCm.flatMap { Int($0) }
                            stressVM.userWeightKg = auth.weightKg.flatMap { Int($0) }
                            stressVM.startSession()
                        } label: {
                            Label("Start Stress Session", systemImage: "play.fill")
                                .measurementPrimaryButtonStyle()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 64)
                        .padding(.top, 8)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                } else if stressVM.phase == .measuring {
                    VStack(spacing: 16) {
                        Spacer()

                        ZStack {
                            CameraPreview(session: stressVM.session)
                                .frame(width: 180, height: 180)
                                .clipShape(Circle())

                            HeartTimerView(
                                heartScale: stressVM.heartScale,
                                secondsLeft: stressVM.secondsLeft,
                                totalSeconds: totalForCurrentPhase,
                                heartSize: 126,
                                color: .purple,
                                showHeart: stressVM.secondsLeft > 0,
                                heartIconScale: 0.78
                            )
                        }

                        if stressVM.canShowBPM, let bpm = stressVM.currentBPM {
                            Text("\(bpm) BPM")
                                .font(.system(size: 42, weight: .bold))
                        } else {
                            Text("Calibrating… keep fingertip on camera")
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                } else if stressVM.phase == .finished {
                    VStack(spacing: 20) {
                        if let bpm = stressVM.currentBPM {
                            Text("Heart Rate: \(bpm) BPM")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            MeasurementStatePromptCard(
                                bpm: bpm,
                                selectedState: $selectedState
                            )
                        }

                        if stressVM.isPredicting {
                            ProgressView("Analysing…")
                        } else if let result = stressVM.stressResult {
                            let pct = result.stressLevelPct
                            let color: Color = pct >= 70 ? .red : pct >= 40 ? .orange : .green
                            let icon = pct >= 50 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"

                            Image(systemName: icon)
                                .font(.system(size: 56))
                                .foregroundColor(color)

                            Text(String(format: "%.0f%%", pct))
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(color)

                            Text(pct >= 70 ? "High Stress" : pct >= 40 ? "Moderate Stress" : "Low Stress")
                                .font(.title3)
                                .foregroundColor(color)
                        } else if let predictionError = stressVM.errorMessage,
                                  stressVM.currentBPM != nil {
                            Text(predictionError)
                                .font(.footnote)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            saveFinishedStressMeasurement()
                        } label: {
                            Label("Save Measurement", systemImage: "checkmark")
                                .measurementPrimaryButtonStyle()
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedState == nil || stressVM.currentBPM == nil || stressVM.isPredicting)
                        .opacity((selectedState == nil || stressVM.currentBPM == nil || stressVM.isPredicting) ? 0.55 : 1)
                        .padding(.horizontal, 64)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }

                Spacer()

                Group {
                    if stressVM.phase == .measuring {
                        Button(role: .destructive) {
                            stressVM.stopSessionEarly()
                        } label: {
                            Text("Stop")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onChange(of: stressVM.phase) { _, newPhase in
            if newPhase != .finished {
                selectedState = nil
            }
        }
        .alert("Flash Unavailable", isPresented: .constant(stressVM.flashUnavailableAlert != nil)) {
            Button("OK") {
                stressVM.flashUnavailableAlert = nil
                stressVM.stopSessionEarly()
            }
        } message: {
            if let alert = stressVM.flashUnavailableAlert {
                Text(alert)
            }
        }
    }

    private func saveFinishedStressMeasurement() {
        guard let bpm = stressVM.currentBPM, let state = selectedState else { return }
        let stress = stressVM.stressResult.map { String(format: "%.0f%%", $0.stressLevelPct) }
        let entry = HeartRateEntry(
            bpm: bpm,
            date: Date(),
            stressLevel: stress,
            activityState: state
        )
        vm.addEntry(entry)
        selectedState = nil
        stressVM.phase = .idle
    }
}

// MARK: - Tap Measurement Content

private struct TapContentView: View {
    @ObservedObject var vm: HeartRateViewModel
    @State private var selectedState: MeasurementState? = nil
    let onStart: () -> Void

    private var totalForCurrentPhase: Int {
        switch vm.phase {
        case .measuring: return 12
        default: return 0
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            switch vm.phase {
            case .idle:
                VStack(spacing: 16) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.bottom, 4)

                    Text("Tap Measurement")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Find your pulse on your neck or wrist, then tap the heart in rhythm for 12 seconds.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button {
                        onStart()
                        vm.startSession()
                    } label: {
                        Label("Start Tap Session", systemImage: "play.fill")
                            .measurementPrimaryButtonStyle()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 64)
                    .padding(.top, 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)

            case .measuring:
                VStack(spacing: 16) {
                    Spacer()

                    HeartTimerView(
                        heartScale: vm.heartScale,
                        secondsLeft: vm.secondsLeft,
                        totalSeconds: totalForCurrentPhase,
                        heartSize: 126,
                        color: .red,
                        heartIconScale: 0.78
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.recordTap()
                    }

                    if let bpm = vm.currentBPM, vm.canShowBPM {
                        Text("\(bpm) BPM")
                            .font(.system(size: 42, weight: .bold))
                    } else if !vm.hasTapped {
                        Text("Tap the heart to begin…")
                            .foregroundColor(.gray)
                    } else {
                        Text("Keep tapping…")
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button("Stop") { vm.stopSession() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(.bottom, 20)
                }

            case .finished:
                VStack(spacing: 16) {
                    if let bpm = vm.currentBPM {
                        Text("\(bpm) BPM")
                            .font(.system(size: 42, weight: .bold))

                        MeasurementStatePromptCard(
                            bpm: bpm,
                            selectedState: $selectedState
                        )

                        Button {
                            saveFinishedTapMeasurement(bpm: bpm)
                        } label: {
                            Label("Save Measurement", systemImage: "checkmark")
                                .measurementPrimaryButtonStyle()
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedState == nil)
                        .opacity(selectedState == nil ? 0.55 : 1)
                        .padding(.horizontal, 64)
                    } else {
                        Text("No data recorded")
                            .foregroundColor(.secondary)
                        Button {
                            vm.startNewSession()
                        } label: {
                            Label("Try Again", systemImage: "arrow.counterclockwise")
                                .measurementPrimaryButtonStyle()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 64)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }

            Spacer()
        }
        .padding()
        .onChange(of: vm.phase) { _, newPhase in
            if newPhase != .finished {
                selectedState = nil
            }
        }
    }

    private func saveFinishedTapMeasurement(bpm: Int) {
        guard let state = selectedState else { return }
        let entry = HeartRateEntry(bpm: bpm, date: Date(), activityState: state)
        vm.addEntry(entry)
        selectedState = nil
        vm.startNewSession()
    }
}

// MARK: - Camera Measurement Content

private struct CameraContentView: View {
    @ObservedObject var vm: HeartRateViewModel
    @ObservedObject var autoVM: AutoHeartRateViewModel
    @State private var selectedState: MeasurementState? = nil
    let onStart: () -> Void

    private var totalForCurrentPhase: Int {
        switch autoVM.phase {
        case .measuring: return 12
        default: return 0
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                if autoVM.phase == .idle {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.bottom, 4)

                        Text("Camera Measurement")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Place your fingertip over the camera and keep it still. The 12-second timer starts after detecting your first beats.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        Button {
                            onStart()
                            autoVM.startSession()
                        } label: {
                            Label("Start Camera Session", systemImage: "play.fill")
                                .measurementPrimaryButtonStyle()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 64)
                        .padding(.top, 8)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                } else if autoVM.phase == .measuring {
                    VStack(spacing: 16) {
                        Spacer()

                        ZStack {
                            CameraPreview(session: autoVM.session)
                                .frame(width: 180, height: 180)
                                .clipShape(Circle())

                            HeartTimerView(
                                heartScale: autoVM.heartScale,
                                secondsLeft: autoVM.secondsLeft,
                                totalSeconds: totalForCurrentPhase,
                                heartSize: 126,
                                color: .red,
                                showHeart: autoVM.secondsLeft > 0,
                                heartIconScale: 0.78
                            )
                        }

                        if autoVM.canShowBPM, let bpm = autoVM.currentBPM {
                            Text("\(bpm) BPM")
                                .font(.system(size: 42, weight: .bold))
                        } else {
                            Text("Calibrating… keep fingertip on camera")
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                } else if autoVM.phase == .finished {
                    VStack(spacing: 16) {
                        if let bpm = autoVM.currentBPM {
                            Text("\(bpm) BPM")
                                .font(.system(size: 42, weight: .bold))

                            MeasurementStatePromptCard(
                                bpm: bpm,
                                selectedState: $selectedState
                            )

                            Button {
                                saveFinishedCameraMeasurement(bpm: bpm)
                            } label: {
                                Label("Save Measurement", systemImage: "checkmark")
                                    .measurementPrimaryButtonStyle()
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedState == nil)
                            .opacity(selectedState == nil ? 0.55 : 1)
                            .padding(.horizontal, 64)
                        } else {
                            Text("No result")
                                .foregroundColor(.secondary)
                            Button {
                                autoVM.phase = .idle
                            } label: {
                                Label("Try Again", systemImage: "arrow.counterclockwise")
                                    .measurementPrimaryButtonStyle()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 64)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }

                Spacer()

                // Bottom-fixed stop button during measurement
                Group {
                    if autoVM.phase == .measuring {
                        Button(role: .destructive) {
                            autoVM.stopSessionEarly()
                        } label: {
                            Text("Stop")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.bottom, 44)
            }
        }
        .onChange(of: autoVM.phase) { _, newPhase in
            if newPhase != .finished {
                selectedState = nil
            }
        }
        .alert("Flash Unavailable", isPresented: .constant(autoVM.flashUnavailableAlert != nil)) {
            Button("OK") {
                autoVM.flashUnavailableAlert = nil
                autoVM.stopSessionEarly()
            }
        } message: {
            if let alert = autoVM.flashUnavailableAlert {
                Text(alert)
            }
        }
    }

    private func saveFinishedCameraMeasurement(bpm: Int) {
        guard let state = selectedState else { return }
        let entry = HeartRateEntry(bpm: bpm, date: Date(), activityState: state)
        vm.addEntry(entry)
        selectedState = nil
        autoVM.phase = .idle
    }
}

private struct MeasurementStatePromptCard: View {
    let bpm: Int
    @Binding var selectedState: MeasurementState?

    private var assessment: HeartRateRangeAssessment? {
        guard let selectedState else { return nil }
        return selectedState.assessment(for: bpm)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("What is your current state?")
                .font(.subheadline.weight(.semibold))

            Picker("Measurement state", selection: $selectedState) {
                Text("Select state").tag(Optional<MeasurementState>.none)
                ForEach(MeasurementState.allCases) { state in
                    Text(state.displayName).tag(Optional(state))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            if let assessment {
                VStack(spacing: 4) {
                    Label(
                        assessment.title,
                        systemImage: assessment.isNormal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(assessment.isNormal ? .green : .orange)

                    Text(assessment.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Choose a state to check whether your BPM is in a normal range.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
}

private extension View {
    func measurementPrimaryButtonStyle() -> some View {
        self
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundColor(.white)
    }
}
