import Foundation
import UserNotifications

enum AlarmNotifier {
    static let categoryId = "PUNCH"
    static let ackAction = "ACK"
    static let snoozeAction = "SNOOZE"
    static let armPrefix = "daka.arm.arrive."

    static func registerCategories() {
        let ack = UNNotificationAction(identifier: ackAction, title: "我已经打卡", options: [.foreground])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "两分钟后再响", options: [])
        let category = UNNotificationCategory(identifier: categoryId, actions: [ack, snooze], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            return true
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(
        kind: ReminderKind,
        placeName: String,
        placeId: UUID,
        eventId: UUID,
        logId: UUID?,
        repeats: Bool
    ) {
        let center = UNUserNotificationCenter.current()
        let count = repeats ? 4 : 1
        for index in 0..<count {
            let content = UNMutableNotificationContent()
            content.title = kind.title
            content.body = body(kind: kind, placeName: placeName)
            content.sound = UNNotificationSound(named: UNNotificationSoundName(kind.soundFile))
            content.categoryIdentifier = categoryId
            var info: [String: Any] = [
                "eventId": eventId.uuidString,
                "placeId": placeId.uuidString,
                "placeName": placeName,
                "kind": kind.rawValue,
            ]
            if let logId {
                info["logId"] = logId.uuidString
            }
            content.userInfo = info
            let trigger: UNNotificationTrigger?
            if index == 0 {
                trigger = nil
            } else {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(index) * 45, repeats: false)
            }
            let request = UNNotificationRequest(
                identifier: "\(eventId.uuidString)-\(index)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    /// Local notifications for someone already inside when the arrive window is still closed.
    static func armArrive(at start: Date, placeId: UUID, placeName: String, eventId: UUID) {
        cancelArmedArrive()
        let center = UNUserNotificationCenter.current()
        for index in 0..<4 {
            let fire = start.addingTimeInterval(Double(index) * 45)
            let interval = fire.timeIntervalSinceNow
            guard interval > 0.5 else { continue }
            let content = UNMutableNotificationContent()
            content.title = ReminderKind.arrive.title
            content.body = "上班时段到了，你还在「\(placeName)」。先在公司打卡 App 里完成定位打卡。"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(ReminderKind.arrive.soundFile))
            content.categoryIdentifier = categoryId
            content.userInfo = [
                "eventId": eventId.uuidString,
                "placeId": placeId.uuidString,
                "placeName": placeName,
                "kind": ReminderKind.arrive.rawValue,
                "arm": "arrive",
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(armPrefix)\(index)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    static func cancelArmedArrive() {
        let ids = (0..<4).map { "\(armPrefix)\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func snooze(userInfo: [AnyHashable: Any]) {
        let content = UNMutableNotificationContent()
        content.title = (userInfo["kind"] as? String).flatMap(ReminderKind.init(rawValue:))?.title ?? "打卡"
        let placeName = userInfo["placeName"] as? String ?? "打卡范围"
        let kind = (userInfo["kind"] as? String).flatMap(ReminderKind.init(rawValue:)) ?? .arrive
        content.body = body(kind: kind, placeName: placeName)
        content.sound = UNNotificationSound(named: UNNotificationSoundName(kind.soundFile))
        content.categoryIdentifier = categoryId
        content.userInfo = userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
        let eventId = userInfo["eventId"] as? String ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: "\(eventId)-snooze", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func cancel(eventId: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.compactMap { request -> String? in
            request.content.userInfo["eventId"] as? String == eventId ? request.identifier : nil
        }
        center.removePendingNotificationRequests(withIdentifiers: ids + ["\(eventId)-snooze"])
        let delivered = await center.deliveredNotifications()
        let deliveredIds = delivered.compactMap { notification -> String? in
            notification.request.content.userInfo["eventId"] as? String == eventId ? notification.request.identifier : nil
        }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
    }

    private static func body(kind: ReminderKind, placeName: String) -> String {
        switch kind {
        case .arrive:
            "你已进入「\(placeName)」。先在公司打卡 App 里完成定位打卡。"
        case .leave:
            "你已离开「\(placeName)」。还没下班打卡的话，先去公司 App 里打。"
        }
    }
}
