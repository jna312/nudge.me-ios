import Foundation
import Combine

#if canImport(AlarmKit)
import AlarmKit
#endif

/// Manages alarm scheduling using AlarmKit (iOS 26+)
/// Falls back to standard notifications on older iOS versions
@MainActor
final class AlarmKitManager: ObservableObject {
    static let shared = AlarmKitManager()
    
    @Published var isAlarmKitAvailable: Bool = false
    @Published var isAuthorized: Bool = false
    @Published var authorizationStatus: String = "Unknown"
    
    private init() {
        checkAvailability()
    }
    
    /// Check if AlarmKit is available on this device
    func checkAvailability() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            isAlarmKitAvailable = true
            Task {
                await checkAuthorization()
            }
        } else {
            isAlarmKitAvailable = false
            authorizationStatus = "Requires iOS 26+"
        }
        #else
        isAlarmKitAvailable = false
        authorizationStatus = "AlarmKit not available"
        #endif
    }
    
    /// Request authorization to use AlarmKit
    func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let granted = try await AlarmManager.shared.requestAuthorization()
                await MainActor.run {
                    self.isAuthorized = granted
                    self.authorizationStatus = granted ? "Authorized" : "Denied"
                }
                print("⏰ AlarmKit authorization: \(granted ? "granted" : "denied")")
                return granted
            } catch {
                await MainActor.run {
                    self.isAuthorized = false
                    self.authorizationStatus = "Error: \(error.localizedDescription)"
                }
                print("⏰ AlarmKit authorization error: \(error)")
                return false
            }
        }
        #endif
        return false
    }
    
    /// Check current authorization status
    func checkAuthorization() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let status = try await AlarmManager.shared.authorizationStatus
                await MainActor.run {
                    switch status {
                    case .authorized:
                        self.isAuthorized = true
                        self.authorizationStatus = "Authorized"
                    case .denied:
                        self.isAuthorized = false
                        self.authorizationStatus = "Denied"
                    case .notDetermined:
                        self.isAuthorized = false
                        self.authorizationStatus = "Not Determined"
                    @unknown default:
                        self.isAuthorized = false
                        self.authorizationStatus = "Unknown"
                    }
                }
            } catch {
                print("⏰ Error checking AlarmKit status: \(error)")
            }
        }
        #endif
    }
    
    /// Schedule an alarm for a reminder (iOS 26+ only)
    /// - Parameters:
    ///   - reminder: The reminder to create an alarm for
    ///   - soundName: The name of the sound file (without extension)
    /// - Returns: True if alarm was scheduled successfully
    func scheduleAlarm(for reminder: ReminderItem, soundName: String) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            guard isAuthorized else {
                print("⏰ AlarmKit not authorized")
                return false
            }
            
            guard let alertAt = reminder.alertAt else {
                print("⏰ No alert time set for reminder")
                return false
            }
            
            do {
                // Create the alarm
                var alarm = Alarm()
                alarm.id = reminder.id.uuidString
                alarm.date = alertAt
                alarm.label = reminder.title
                alarm.isEnabled = true
                
                // Set the sound - AlarmKit can use bundled sounds
                if soundName != "default" && !soundName.isEmpty {
                    if let soundURL = Bundle.main.url(forResource: soundName, withExtension: "caf") {
                        alarm.sound = .custom(soundURL)
                    } else {
                        alarm.sound = .default
                    }
                } else {
                    alarm.sound = .default
                }
                
                // Schedule the alarm
                try await AlarmManager.shared.schedule(alarm)
                print("⏰ Scheduled AlarmKit alarm for '\(reminder.title)' at \(alertAt)")
                return true
                
            } catch {
                print("⏰ Error scheduling AlarmKit alarm: \(error)")
                return false
            }
        }
        #endif
        return false
    }
    
    /// Cancel an alarm for a reminder
    func cancelAlarm(for reminder: ReminderItem) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                try await AlarmManager.shared.cancel(identifier: reminder.id.uuidString)
                print("⏰ Cancelled AlarmKit alarm for '\(reminder.title)'")
            } catch {
                print("⏰ Error cancelling AlarmKit alarm: \(error)")
            }
        }
        #endif
    }
    
    /// Cancel all alarms
    func cancelAllAlarms() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                try await AlarmManager.shared.cancelAll()
                print("⏰ Cancelled all AlarmKit alarms")
            } catch {
                print("⏰ Error cancelling all AlarmKit alarms: \(error)")
            }
        }
        #endif
    }
    
    /// Get all scheduled alarms
    func getScheduledAlarms() async -> [String] {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let alarms = try await AlarmManager.shared.scheduledAlarms
                return alarms.map { $0.id }
            } catch {
                print("⏰ Error getting scheduled alarms: \(error)")
            }
        }
        #endif
        return []
    }
}

// MARK: - Alarm Action Handling
extension AlarmKitManager {
    /// Handle alarm actions (snooze, stop, etc.)
    func handleAlarmAction(alarmID: String, action: AlarmAction) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch action {
            case .stop:
                await cancelAlarmByID(alarmID)
            case .snooze(let minutes):
                await snoozeAlarm(alarmID: alarmID, minutes: minutes)
            }
        }
        #endif
    }
    
    private func cancelAlarmByID(_ alarmID: String) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                try await AlarmManager.shared.cancel(identifier: alarmID)
            } catch {
                print("⏰ Error cancelling alarm: \(error)")
            }
        }
        #endif
    }
    
    private func snoozeAlarm(alarmID: String, minutes: Int) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let snoozeDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
                try await AlarmManager.shared.snooze(identifier: alarmID, until: snoozeDate)
                print("⏰ Snoozed alarm \(alarmID) for \(minutes) minutes")
            } catch {
                print("⏰ Error snoozing alarm: \(error)")
            }
        }
        #endif
    }
}

/// Alarm actions that can be taken
enum AlarmAction {
    case stop
    case snooze(minutes: Int)
}
