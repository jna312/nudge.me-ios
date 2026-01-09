import SwiftUI

struct RootView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Root View")
                    .font(.title)
                Text("Onboarding complete: \(settings.didCompleteOnboarding.description)")
                Button("Reset Onboarding") {
                    settings.didCompleteOnboarding = false
                }
            }
            .padding()
            .navigationTitle("Nudge")
        }
    }
}

#Preview {
    RootView(settings: AppSettings(didCompleteOnboarding: true))
}
