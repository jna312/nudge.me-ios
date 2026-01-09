import SwiftUI

struct RootView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            ContentView()
                .environmentObject(settings)
                .tabItem { Label("Speak", systemImage: "mic.fill") }

            NavigationStack { TodayView() }
                .environmentObject(settings)
                .tabItem { Label("Today", systemImage: "checklist") }
        }
    }
}
