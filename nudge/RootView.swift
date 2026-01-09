import SwiftUI

struct RootView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Speak", systemImage: "mic.fill") }

            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "checklist") }
        }
    }
}
