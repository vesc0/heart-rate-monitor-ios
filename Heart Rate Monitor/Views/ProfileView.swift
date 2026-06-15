import SwiftUI

enum ProfileUnitSystem: String, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @AppStorage("profile.unitSystem") private var preferredUnitSystemRaw = ProfileUnitSystem.metric.rawValue
    @State private var showAuthSheet = false
    @State private var selectedAuthTab = 0 // 0 = Login, 1 = Sign Up
    @State private var editingField: EditableField? = nil
    @State private var profileError: String?

    enum EditableField: String, CaseIterable, Identifiable {
        case name, email, age, gender, height, weight, health
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView {
                        Group {
                            if auth.isSignedIn {
                                signedInContent
                            } else {
                                signedOutContent
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: proxy.size.height,
                            alignment: auth.isSignedIn ? .top : .center
                        )
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollBounceBehavior(.always)
                    .scrollIndicators(.hidden)
                }
            }
            .id(auth.isSignedIn)
            .sheet(isPresented: $showAuthSheet) {
                AuthSheetView(selectedTab: $selectedAuthTab)
                    .environmentObject(auth)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
            }
            .sheet(item: $editingField) { field in
                EditFieldSheet(
                    field: field,
                    initialValue: currentValue(for: field),
                    onSave: { newValue in
                        saveProfileField(field, newValue: newValue)
                        editingField = nil
                    },
                    onCancel: { editingField = nil }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
                .interactiveDismissDisabled(false)
            }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    showAuthSheet = false
                    profileError = nil
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("Welcome")
                    .font(.title2).fontWeight(.bold)
                Text("Log in to sync your measurements,\nview stats, and manage your profile.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            Button {
                selectedAuthTab = 0
                showAuthSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Log In or Sign Up")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
    }

    // MARK: - Signed In

    private var signedInContent: some View {
        VStack(spacing: 20) {
            profileHeaderCard
                .padding(.top, 8)

            // Details section
            VStack(alignment: .leading, spacing: 10) {
                Text("Details")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 6)

                VStack(spacing: 0) {
                    profileRow(icon: "calendar", label: "Age", value: auth.age ?? "", editable: .age)
                    Divider().padding(.leading, 48)
                    profileRow(icon: "figure.stand", label: "Gender", value: (auth.gender ?? "").capitalized, editable: .gender)
                    Divider().padding(.leading, 48)
                    profileRow(icon: "ruler", label: "Height", value: displayedHeight, editable: .height)
                    Divider().padding(.leading, 48)
                    profileRow(icon: "scalemass", label: "Weight", value: displayedWeight, editable: .weight)
                    Divider().padding(.leading, 48)
                    profileRow(icon: "heart.text.clipboard", label: "Health", value: auth.healthIssues ?? "", editable: .health)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }

            if let err = profileError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            // Sign out
            Button(role: .destructive) {
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.warning)
                auth.signOut()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .foregroundStyle(Color.red.opacity(0.9))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.red.opacity(0.22), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header Card

    private var profileHeaderCard: some View {
        HStack(alignment: .center, spacing: 14) {
            profileAvatar

            VStack(spacing: 0) {
                profileRow(
                    icon: "person.fill",
                    label: "Name",
                    value: auth.name ?? "",
                    editable: .name,
                    placeholder: "Your Name"
                )
                Divider().padding(.leading, 48)
                profileRow(
                    icon: "envelope.fill",
                    label: "Email",
                    value: auth.currentEmail ?? "",
                    editable: .email
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var profileAvatar: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [.pink, .red, .orange, .pink]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 94, height: 94)
                .opacity(0.6)

            Circle()
                .fill(Color(.tertiarySystemGroupedBackground))
                .frame(width: 86, height: 86)
                .overlay(
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(12)
                )
        }
    }

    // MARK: - Profile Row

    @ViewBuilder
    func profileRow(icon: String, label: String, value: String, editable: EditableField, placeholder: String = "Not set") -> some View {
        Button {
            editingField = editable
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.red)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value.isEmpty ? placeholder : value)
                        .font(.body)
                        .foregroundColor(value.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Profile helpers

    private var preferredUnitSystem: ProfileUnitSystem {
        ProfileUnitSystem(rawValue: preferredUnitSystemRaw) ?? .metric
    }

    private var displayedHeight: String {
        guard let cm = Int(auth.heightCm ?? "") else { return "" }
        if preferredUnitSystem == .metric {
            return "\(cm) cm"
        }
        let totalInches = Int((Double(cm) / 2.54).rounded())
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet) ft \(inches) in"
    }

    private var displayedWeight: String {
        guard let kg = Int(auth.weightKg ?? "") else { return "" }
        if preferredUnitSystem == .metric {
            return "\(kg) kg"
        }
        let lb = Int((Double(kg) * 2.2046226218).rounded())
        return "\(lb) lb"
    }

    private func currentValue(for field: EditableField) -> String {
        switch field {
        case .name:   return auth.name ?? ""
        case .email:  return auth.currentEmail ?? ""
        case .age:    return auth.age ?? ""
        case .gender: return auth.gender ?? ""
        case .height: return auth.heightCm ?? ""
        case .weight: return auth.weightKg ?? ""
        case .health: return auth.healthIssues ?? ""
        }
    }

    private func saveProfileField(_ field: EditableField, newValue: String) {
        guard auth.isSignedIn else { return }
        Task {
            do {
                switch field {
                case .name:
                    try await auth.updateProfile(name: newValue)
                case .email:
                    try await auth.updateProfile(email: newValue)
                case .age:
                    try await auth.updateProfile(age: Int(newValue))
                case .gender:
                    try await auth.updateProfile(gender: newValue.lowercased())
                case .height:
                    try await auth.updateProfile(heightCm: Int(newValue))
                case .weight:
                    try await auth.updateProfile(weightKg: Int(newValue))
                case .health:
                    try await auth.updateProfile(healthIssues: newValue)
                }
                profileError = nil
            } catch {
                profileError = error.localizedDescription
            }
        }
    }
}

// MARK: - Auth Sheet (presented as .sheet — handles keyboard natively)

struct AuthSheetView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Log In").tag(0)
                    Text("Sign Up").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 12)

                ScrollView {
                    if selectedTab == 0 {
                        LoginView(inPopup: true)
                            .environmentObject(auth)
                            .padding(.horizontal)
                    } else {
                        SignUpView(inPopup: true)
                            .environmentObject(auth)
                            .padding(.horizontal)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
            .navigationTitle(selectedTab == 0 ? "Log In" : "Sign Up")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Inline sheet for editing fields
struct EditFieldSheet: View {
    let field: ProfileView.EditableField
    let initialValue: String
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""
    @State private var numericValue: Int = 0
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 7
    @State private var selectedGender: String = "other"
    @State private var unitSystem: ProfileUnitSystem = .metric
    @State private var previousUnitSystem: ProfileUnitSystem = .metric
    @State private var isInitializing = false
    @AppStorage("profile.unitSystem") private var preferredUnitSystemRaw = ProfileUnitSystem.metric.rawValue
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 14) {
                        fieldEditor
                        
                        Button {
                            onSave(saveValue)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                            .frame(width: 180)
                            .padding()
                            .background(LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(!canSave)
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit \(fieldName)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                draft = initialValue
                initializeState()
            }
        }
    }

    @ViewBuilder
    private var fieldEditor: some View {
        switch field {
        case .age:
            wheelEditor(
                valueText: "\(numericValue) years",
                selection: $numericValue,
                values: Array(1...130)
            )
        case .height:
            VStack(alignment: .leading, spacing: 10) {
                unitPicker
                heightWheelEditor(valueText: heightDisplay)
            }
        case .weight:
            VStack(alignment: .leading, spacing: 10) {
                unitPicker
                weightWheelEditor(
                    valueText: weightDisplay,
                    selection: $numericValue
                )
            }
        case .gender:
            Picker("Gender", selection: $selectedGender) {
                Text("Male").tag("male")
                Text("Female").tag("female")
                Text("Other").tag("other")
            }
            .pickerStyle(.segmented)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .light ? 0.06 : 0), radius: 8, x: 0, y: 3)
        default:
            TextField(fieldName, text: $draft, axis: field == .health ? .vertical : .horizontal)
                .focused($textFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(autocapitalization)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(field != .name)
                .lineLimit(field == .health ? 6 : 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .shadow(color: .black.opacity(colorScheme == .light ? 0.06 : 0), radius: 8, x: 0, y: 3)
                .foregroundColor(.primary)
        }
    }

    private var unitPicker: some View {
        Picker("Units", selection: $unitSystem) {
            ForEach(ProfileUnitSystem.allCases) { unit in
                Text(unit == .metric ? "Metric" : "Imperial")
                    .tag(unit)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: unitSystem) { _, newUnit in
            guard !isInitializing else { return }
            guard newUnit != previousUnitSystem else { return }
            preferredUnitSystemRaw = newUnit.rawValue
            // Keep the represented value equivalent while toggling units.
            if field == .height {
                if newUnit == .imperial {
                    syncImperialHeightFromMetricCm(numericValue)
                } else {
                    numericValue = clamped(metricCmFromImperialHeight, to: heightRange)
                }
            } else if field == .weight {
                let converted = newUnit == .metric
                    ? (Double(numericValue) / 2.2046226218)
                    : (Double(numericValue) * 2.2046226218)
                numericValue = clamped(Int(converted.rounded()), to: weightRange)
            }
            previousUnitSystem = newUnit
        }
    }

    private func wheelEditor(valueText: String, selection: Binding<Int>, values: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(valueText)
                .font(.title2)
                .fontWeight(.semibold)

            Picker("", selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text("\(value)")
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .light ? 0.06 : 0), radius: 8, x: 0, y: 3)
    }

    private func heightWheelEditor(valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(valueText)
                .font(.title2)
                .fontWeight(.semibold)

            if unitSystem == .metric {
                Picker("", selection: $numericValue) {
                    ForEach(Array(heightRange), id: \.self) { value in
                        Text("\(value) cm").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
            } else {
                HStack(spacing: 0) {
                    Picker("Feet", selection: $heightFeet) {
                        ForEach(1...8, id: \.self) { value in
                            Text("\(value) ft").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Inches", selection: $heightInches) {
                        ForEach(0...11, id: \.self) { value in
                            Text("\(value) in").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 160)
                .onChange(of: heightFeet) { _, _ in
                    clampImperialHeightSelection()
                }
                .onChange(of: heightInches) { _, _ in
                    clampImperialHeightSelection()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .light ? 0.06 : 0), radius: 8, x: 0, y: 3)
    }

    private func weightWheelEditor(valueText: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(valueText)
                .font(.title2)
                .fontWeight(.semibold)

            Picker("", selection: selection) {
                ForEach(Array(weightRange), id: \.self) { value in
                    Text(unitSystem == .metric ? "\(value) kg" : "\(value) lb")
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .light ? 0.06 : 0), radius: 8, x: 0, y: 3)
    }

    private func initializeState() {
        isInitializing = true
        unitSystem = ProfileUnitSystem(rawValue: preferredUnitSystemRaw) ?? .metric
        previousUnitSystem = unitSystem
        switch field {
        case .age:
            numericValue = clamped(Int(initialValue) ?? 30, to: 1...130)
        case .height:
            let metricCm = clamped(Int(initialValue) ?? 170, to: 50...250)
            if unitSystem == .metric {
                numericValue = metricCm
            } else {
                syncImperialHeightFromMetricCm(metricCm)
            }
        case .weight:
            let metricKg = clamped(Int(initialValue) ?? 70, to: 20...300)
            if unitSystem == .metric {
                numericValue = metricKg
            } else {
                let lb = Int((Double(metricKg) * 2.2046226218).rounded())
                numericValue = clamped(lb, to: weightRange)
            }
        case .gender:
            let normalized = initialValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            selectedGender = ["male", "female", "other"].contains(normalized) ? normalized : "other"
        default:
            textFocused = true
        }
        preferredUnitSystemRaw = unitSystem.rawValue
        isInitializing = false
    }

    private var saveValue: String {
        switch field {
        case .age:
            return String(numericValue)
        case .height:
            let cm = unitSystem == .metric ? Double(numericValue) : (Double(metricCmFromImperialHeight))
            return String(Int(cm.rounded()))
        case .weight:
            let kg = unitSystem == .metric ? Double(numericValue) : (Double(numericValue) / 2.2046226218)
            return String(Int(kg.rounded()))
        case .gender:
            return selectedGender
        default:
            return trimmedDraft
        }
    }

    private var canSave: Bool {
        switch field {
        case .age, .height, .weight, .gender:
            return true
        default:
            return !trimmedDraft.isEmpty
        }
    }

    private var heightDisplay: String {
        if unitSystem == .metric {
            return "\(numericValue) cm"
        }
        return "\(heightFeet) ft \(heightInches) in"
    }

    private var weightDisplay: String {
        if unitSystem == .metric {
            return "\(numericValue) kg"
        }
        return "\(numericValue) lb"
    }

    private var heightRange: ClosedRange<Int> {
        unitSystem == .metric ? 50...250 : 20...98
    }

    private var weightRange: ClosedRange<Int> {
        unitSystem == .metric ? 20...300 : 44...661
    }

    private func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private var metricCmFromImperialHeight: Int {
        let totalInches = (heightFeet * 12) + heightInches
        let clampedInches = clamped(totalInches, to: 20...98)
        return Int((Double(clampedInches) * 2.54).rounded())
    }

    private func syncImperialHeightFromMetricCm(_ cm: Int) {
        let inches = clamped(Int((Double(cm) / 2.54).rounded()), to: 20...98)
        heightFeet = inches / 12
        heightInches = inches % 12
    }

    private func clampImperialHeightSelection() {
        let inches = clamped((heightFeet * 12) + heightInches, to: 20...98)
        heightFeet = inches / 12
        heightInches = inches % 12
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var keyboardType: UIKeyboardType {
        switch field {
        case .email:
            return .emailAddress
        case .age, .height, .weight:
            return .numberPad
        default:
            return .default
        }
    }

    private var autocapitalization: TextInputAutocapitalization {
        switch field {
        case .name:
            return .words
        case .health:
            return .sentences
        default:
            return .never
        }
    }

    private var fieldName: String {
        switch field {
        case .name:   return "Name"
        case .email:  return "Email"
        case .age:    return "Age"
        case .gender: return "Gender"
        case .height: return "Height"
        case .weight: return "Weight"
        case .health: return "Health Issues"
        }
    }
}

