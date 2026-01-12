import LocalAuthentication
import SwiftUI

final class BiometricAuth: ObservableObject {
    static let shared = BiometricAuth()
    
    @Published var isUnlocked = false
    @Published var isAuthenticating = false
    
    private init() {}
    
    var biometricType: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Passcode"
        @unknown default:
            return "Biometrics"
        }
    }
    
    var isBiometricsAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
    
    func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            await MainActor.run { isUnlocked = true }
            return true
        }
        
        await MainActor.run { isAuthenticating = true }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Nudge to access your reminders"
            )
            await MainActor.run {
                isUnlocked = success
                isAuthenticating = false
            }
            return success
        } catch {
            await MainActor.run { isAuthenticating = false }
            return false
        }
    }
    
    func lock() {
        isUnlocked = false
    }
}

struct LockScreenView: View {
    @ObservedObject var auth = BiometricAuth.shared
    @State private var showError = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 16) {
                    Text("n")
                        .font(.custom("Snell Roundhand", size: 120))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text("nudge")
                        .font(.custom("Snell Roundhand", size: 32))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button {
                        Task {
                            let success = await auth.authenticate()
                            if !success { showError = true }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: auth.isBiometricsAvailable ? 
                                  (BiometricAuth.shared.biometricType == "Face ID" ? "faceid" : "touchid") : 
                                  "lock.fill")
                                .font(.title2)
                            Text("Unlock with \(auth.biometricType)")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(auth.isAuthenticating)
                    .opacity(auth.isAuthenticating ? 0.6 : 1)
                    
                    if auth.isAuthenticating {
                        ProgressView().tint(.white)
                    }
                }
                
                Spacer().frame(height: 60)
            }
        }
        .alert("Authentication Failed", isPresented: $showError) {
            Button("Try Again") { Task { await auth.authenticate() } }
            Button("Cancel", role: .cancel) {}
        }
        .task { await auth.authenticate() }
    }
}
