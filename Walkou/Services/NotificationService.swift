import Foundation
import UserNotifications
import UIKit

/// Local notifications for moments that matter while the phone is in a pocket.
enum NotificationService {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Shows a notification right away, but only when the app isn't on screen.
    @MainActor
    static func notifyIfInBackground(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
enum Haptics {
    // Reused and pre-warmed: creating a generator per tap stalls the main thread for a frame or two.
    private static let impact: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        return generator
    }()
    private static let notification: UINotificationFeedbackGenerator = {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    static func gem(_ kind: GemKind) {
        switch kind {
        case .common:
            impact.impactOccurred(intensity: 0.8)
        case .legendary:
            notification.notificationOccurred(.success)
            notification.prepare()
        default:
            heavy.impactOccurred()
            heavy.prepare()
        }
        impact.prepare()
    }

    private static let heavy: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        return generator
    }()

    static func tap() {
        impact.impactOccurred()
        impact.prepare()
    }
}
