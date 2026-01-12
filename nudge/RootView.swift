import SwiftUI

enum AppTab: Int {
    case speak = 0
    case reminders = 1
}

struct RootView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var notificationsManager = NotificationsManager.shared
    @State private var selectedTab: AppTab = .speak
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // MAIN UI (Speak)
            NavigationStack {
                ContentView(isSettingsOpen: $showSettings)
                    .environmentObject(settings)
                    .navigationTitle("Nudge")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                    .sheet(isPresented: $showSettings) {
                        NavigationStack {
                            SettingsView(settings: settings)
                                .navigationTitle("Settings")
                        }
                    }
            }
            .tabItem { Label("Speak", systemImage: "mic.fill") }
            .tag(AppTab.speak)

            // Reminders
            NavigationStack {
                RemindersView()
                    .environmentObject(settings)
            }
            .tabItem { Label("Reminders", systemImage: "list.bullet.circle") }
            .tag(AppTab.reminders)
        }
        .onChange(of: notificationsManager.shouldNavigateToReminders) { _, shouldNavigate in
            if shouldNavigate {
                selectedTab = .reminders
                // Reset the flag
                notificationsManager.shouldNavigateToReminders = false
            }
        }
    }
}
