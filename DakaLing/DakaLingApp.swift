import SwiftUI
import UIKit
import UserNotifications

@main
struct DakaLingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
                .tint(Theme.cinnabar)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            AppModel.shared.start()
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let kind = (notification.request.content.userInfo["kind"] as? String).flatMap(ReminderKind.init(rawValue:)) ?? .arrive
        let isArm = notification.request.identifier.hasPrefix(AlarmNotifier.armPrefix)
        let play = await MainActor.run { () -> Bool? in
            guard AppModel.shared.remindersOn else {
                AppModel.shared.stopAlarmPlayback()
                return nil
            }
            if isArm {
                return AppModel.shared.noteArmedArrive(userInfo: notification.request.content.userInfo)
            }
            return true
        }
        guard let play else { return [] }
        if play {
            await MainActor.run {
                let info = notification.request.content.userInfo
                let eventId = (info["eventId"] as? String).flatMap(UUID.init(uuidString:))
                let placeName = info["placeName"] as? String
                AppModel.shared.presentAlarm(kind: kind, eventId: eventId, placeName: placeName)
            }
        }
        return [.banner, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            AppModel.shared.handleNotification(response)
        }
    }
}
