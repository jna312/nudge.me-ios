import SwiftUI
import Combine

// MARK: - Tips Manager

final class TipsManager: ObservableObject {
    static let shared = TipsManager()
    
    @Published var currentTip: Tip? = nil
    
    private let defaults = UserDefaults.standard
    
    private var holdToSpeakShown: Bool {
        get { defaults.bool(forKey: "tip_holdToSpeak_shown") }
        set { defaults.set(newValue, forKey: "tip_holdToSpeak_shown") }
    }
    
    private var swipeActionsShown: Bool {
        get { defaults.bool(forKey: "tip_swipeActions_shown") }
        set { defaults.set(newValue, forKey: "tip_swipeActions_shown") }
    }
    
    private var voiceCommandsShown: Bool {
        get { defaults.bool(forKey: "tip_voiceCommands_shown") }
        set { defaults.set(newValue, forKey: "tip_voiceCommands_shown") }
    }
    
    private var undoBannerShown: Bool {
        get { defaults.bool(forKey: "tip_undoBanner_shown") }
        set { defaults.set(newValue, forKey: "tip_undoBanner_shown") }
    }
    
    private var quickAddShown: Bool {
        get { defaults.bool(forKey: "tip_quickAdd_shown") }
        set { defaults.set(newValue, forKey: "tip_quickAdd_shown") }
    }
    
    enum TipID: String {
        case holdToSpeak
        case swipeActions
        case voiceCommands
        case undoBanner
        case quickAdd
    }
    
    struct Tip: Identifiable, Equatable {
        let id: TipID
        let title: String
        let message: String
        let icon: String
    }
    
    private init() {}
    
    func showTipIfNeeded(_ tipID: TipID) {
        switch tipID {
        case .holdToSpeak:
            guard !holdToSpeakShown else { return }
            currentTip = Tip(
                id: .holdToSpeak,
                title: String(localized: "Hold to Speak"),
                message: String(localized: "Hold the mic button and say your reminder with a time, like \"Call mom tomorrow at 3 PM\""),
                icon: "hand.tap.fill"
            )
            
        case .swipeActions:
            guard !swipeActionsShown else { return }
            currentTip = Tip(
                id: .swipeActions,
                title: String(localized: "Swipe for Actions"),
                message: String(localized: "Swipe left to delete, swipe right to snooze. Tap the circle to complete."),
                icon: "hand.draw"
            )
            
        case .voiceCommands:
            guard !voiceCommandsShown else { return }
            currentTip = Tip(
                id: .voiceCommands,
                title: String(localized: "Voice Commands"),
                message: String(localized: "Try saying \"Cancel my last reminder\" or \"Change dentist to 4 PM\""),
                icon: "mic.fill"
            )
            
        case .undoBanner:
            guard !undoBannerShown else { return }
            currentTip = Tip(
                id: .undoBanner,
                title: String(localized: "Quick Undo"),
                message: String(localized: "Made a mistake? Tap Undo within 5 seconds to delete the reminder."),
                icon: "arrow.uturn.backward"
            )
            
        case .quickAdd:
            guard !quickAddShown else { return }
            currentTip = Tip(
                id: .quickAdd,
                title: String(localized: "Quick Time Buttons"),
                message: String(localized: "Tap the time chips for common options like \"30 min\" or \"Tomorrow 9 AM\""),
                icon: "clock"
            )
        }
    }
    
    func dismissTip(_ tipID: TipID) {
        currentTip = nil
        
        switch tipID {
        case .holdToSpeak:
            holdToSpeakShown = true
        case .swipeActions:
            swipeActionsShown = true
        case .voiceCommands:
            voiceCommandsShown = true
        case .undoBanner:
            undoBannerShown = true
        case .quickAdd:
            quickAddShown = true
        }
    }
    
    func resetAllTips() {
        holdToSpeakShown = false
        swipeActionsShown = false
        voiceCommandsShown = false
        undoBannerShown = false
        quickAddShown = false
        currentTip = nil
    }
}

// MARK: - Tip Overlay View

struct TipOverlay: View {
    let tip: TipsManager.Tip
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: tip.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip.title)
                            .font(.headline)
                        Text(tip.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                
                Button("Got it") {
                    withAnimation(.spring(response: 0.3)) {
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
