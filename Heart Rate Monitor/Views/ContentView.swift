//
//  ContentView.swift
//  Heart Rate Monitor
//
//  Created by Vesco on 9/3/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = HeartRateViewModel()
    @StateObject private var auth = AuthViewModel()
    @State private var selectedTab = 1
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MeasurementView(vm: vm)
                .tabItem {
                    Label("Measure", systemImage: "heart.fill")
                }
                .tag(1)

            HistoryView(vm: vm)
                .tabItem {
                    Label("Stats", systemImage: "list.bullet")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(3)

            SettingsView(vm: vm)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
        .environmentObject(auth)
        // Sync heart-rate data when auth state changes
        // Returning to the app is the usual moment a queued measurement can finally sync.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.refreshFromServer() }
        }
        .onChange(of: auth.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                vm.refreshFromServer()
            } else {
                vm.clearForLogout()
            }
        }
    }
}

#Preview {
    ContentView()
}

