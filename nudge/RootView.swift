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
    @State private var shouldAutoStartMic = false
    @State private var selectedReminderID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            // MAIN UI (Speak)
            NavigationStack {
                ContentView(isSettingsOpen: $showSettings, autoStartMic: $shouldAutoStartMic)
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
                RemindersView(selectedReminderID: $selectedReminderID)
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
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .task {
            // Start calendar auto-sync if enabled
            if settings.calendarSyncEnabled {
                CalendarSync.shared.startAutoSync(frequency: settings.calendarSyncFrequency, context: modelContext)
            }
            
            // Sync reminders to widget
            WidgetDataProvider.shared.syncReminders(from: modelContext)
            
            // Check for widget completions
            WidgetDataProvider.shared.checkForWidgetCompletions(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Check for widget completions when app becomes active
            WidgetDataProvider.shared.checkForWidgetCompletions(in: modelContext)
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "nudge" else { return }
        
        switch url.host {
        case "voice":
            // Open to speak tab and auto-start mic
            selectedTab = .speak
            shouldAutoStartMic = true
            
        case "reminder":
            // Open specific reminder
            if let idString = url.pathComponents.last,
               let uuid = UUID(uuidString: idString) {
                selectedTab = .reminders
                selectedReminderID = uuid
            }
            
        case "reminders":
            // Just open reminders tab
            selectedTab = .reminders
            
        default:
            break
        }
    }
}
