import SwiftUI

struct RootView: View {
    @ObservedObject var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        TabView {
            // MAIN UI (Speak)
            NavigationStack {
                ContentView()
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

            // Today
            NavigationStack {
                TodayView()
                    .navigationTitle("Today")
            }
            .tabItem { Label("Today", systemImage: "checklist") }
        }
    }
}
