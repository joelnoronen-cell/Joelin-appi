import Foundation
import UserNotifications

/// Schedules a local notification shortly before each timed plan.
@MainActor
enum ReminderScheduler {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.remindersEnabled)
    }

    static var leadMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: SettingsKey.reminderLead)
        return value > 0 ? value : 10
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    /// Brings the pending notification for `plan` in line with its current state.
    static func sync(_ plan: Plan) {
        let center = UNUserNotificationCenter.current()
        let identifier = plan.uid.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard isEnabled, plan.remind, !plan.isDone, !plan.isAnytime else { return }
        let lead = leadMinutes
        let fireDate = plan.start.addingTimeInterval(TimeInterval(-lead * 60))
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = "Starts in \(Fmt.spokenDuration(lead)), at \(Fmt.time(plan.start))."
        content.sound = .default

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    static func resync(_ plans: [Plan]) {
        for plan in plans where plan.start > .now || !isEnabled {
            sync(plan)
        }
    }

    static func cancel(_ plan: Plan) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [plan.uid.uuidString])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
