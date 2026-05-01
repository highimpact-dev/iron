import Foundation
import UserNotifications

@MainActor
enum RestNotificationService {
    private static let identifier = "iron.rest-complete"
    private static let countdownLeadSeconds: TimeInterval = 10
    private static let soundName = UNNotificationSoundName("countdown.caf")

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(endsAt: Date, exerciseName: String) {
        cancel()
        let fireAt = endsAt.addingTimeInterval(-countdownLeadSeconds)
        let interval = fireAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Almost up"
        content.body = "Back to \(exerciseName) — 10 seconds."
        content.sound = UNNotificationSound(named: soundName)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
