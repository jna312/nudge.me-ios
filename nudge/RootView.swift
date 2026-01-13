import SwiftUI
import SwiftData

enum AppTab: Int {
    case speak = 0
    case reminders = 1
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
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
                    .navigationBarTitleDisplayMode(.inline)
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
                notificationsManager.shouldNavigateToReminders = false
            }
        }
        .task {
            // Start calendar auto-sync if enabled
            if settings.calendarSyncEnabled {
                CalendarSync.shared.startAutoSync(frequency: settings.calendarSyncFrequency, context: modelContext)
            }
        }
    }
}
