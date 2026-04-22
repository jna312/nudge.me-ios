import Foundation

/// Owns a single silence-detection timer used by the auto-listening flow in
/// `ContentView` and `TodayView`. Invalidates any existing timer before
/// scheduling a new one, and hops to the main queue before firing.
@MainActor
final class SilenceTimerController {
    private var timer: Timer?

    /// Schedule a one-shot timer that fires `onFire` after `timeout` seconds
    /// of silence. Any previously scheduled timer is invalidated first.
    func schedule(timeout: TimeInterval, onFire: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            DispatchQueue.main.async {
                onFire()
            }
        }
    }

    /// Cancel any scheduled timer.
    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
