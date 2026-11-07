import Foundation
import UserNotifications

/// Local notifications for the timer.
///
/// Two moments matter, and only two:
/// - just before the estimate runs out, so the user can still finish early;
/// - when the estimate is actually up, in case they forgot to stop.
///
/// The congratulation for banking time stays **in the app** (haptic + banner)
/// rather than becoming a notification — the user is looking at the screen
/// when they finish, and a notification for something they just watched happen
/// is noise.
///
/// Permission is asked for the first time the user starts a real task, never
/// at launch: a permission dialog with no context is the fastest way to get
/// denied, and App Review frowns on prompts that appear before the user has
/// seen what the app does.
@MainActor
enum VaultNotifier {

    private static let estimateReminderID = "vault.estimate.reminder"
    private static let estimateUpID = "vault.estimate.up"

    /// Whether the user has already been asked. Stored so we only ever ask once.
    private static let hasAskedKey = "vault.hasAskedNotificationPermission"

    static func requestPermissionIfNeeded() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasAskedKey) { return }
        defaults.set(true, forKey: hasAskedKey)

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        default:
            break
        }
    }

    /// Schedule the two reminders for a running task.
    ///
    /// - Parameter estimatedSeconds: the locked estimate.
    /// - Parameter taskID: used to build unique request identifiers.
    static func scheduleReminders(taskID: Int64, estimatedSeconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [estimateReminderID(taskID), estimateUpID(taskID)]
        )

        guard estimatedSeconds > 0 else { return }
        let now = Date()

        // "Almost up" — only if there is enough time for the notification to
        // make sense (a 20-second task does not deserve a reminder at 0).
        let reminderDelay = estimatedSeconds - 60
        if reminderDelay >= 10 {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("notif_almost_title", comment: "")
            content.body = NSLocalizedString("notif_almost_body", comment: "")
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(reminderDelay), repeats: false)
            let request = UNNotificationRequest(
                identifier: estimateReminderID(taskID),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }

        // "Time is up".
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notif_over_title", comment: "")
        content.body = NSLocalizedString("notif_over_body", comment: "")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(estimatedSeconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: estimateUpID(taskID),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Clear the reminders for a task that is no longer running.
    static func cancelReminders(taskID: Int64) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [estimateReminderID(taskID), estimateUpID(taskID)]
        )
    }

    private static func estimateReminderID(_ taskID: Int64) -> String {
        "\(estimateReminderID).\(taskID)"
    }

    private static func estimateUpID(_ taskID: Int64) -> String {
        "\(estimateUpID).\(taskID)"
    }
}
