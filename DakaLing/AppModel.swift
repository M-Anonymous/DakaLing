import CoreLocation
import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var places: [Place] = []
    private(set) var logs: [ReminderLog] = []
    private(set) var remindersOn = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation?
    private(set) var statusMessage: String?
    private(set) var ringingKind: ReminderKind?
    private(set) var ringingPlaceName: String?

    var arriveWindow = PunchWindow.arrive
    var leaveWindow = PunchWindow.leave

    private let monitor = GeofenceMonitor()
    private var insideIds: Set<String> = []
    private var started = false
    private var arriveRemindedDay: String?
    private var leaveRemindedDay: String?
    private var armedFireAt: Date?
    private var armedEventId: UUID?
    private var armedPlaceId: UUID?
    private var ringingEventId: UUID?
    private var watchTask: Task<Void, Never>?
    private var suppressArriveTickUntil: Date?
    private var notificationsAllowed = false

    private let placesKey = "daka.places"
    private let logsKey = "daka.logs"
    private let remindersKey = "daka.remindersOn"
    private let insideKey = "daka.insideIds"
    private let arriveWindowKey = "daka.arriveWindow"
    private let leaveWindowKey = "daka.leaveWindow"
    private let arriveDayKey = "daka.arriveRemindedDay"
    private let leaveDayKey = "daka.leaveRemindedDay"
    private let armedFireKey = "daka.armedFireAt"
    private let armedEventKey = "daka.armedEventId"
    private let armedPlaceKey = "daka.armedPlaceId"
    private let notificationsKey = "daka.notificationsAllowed"

    private init() {
        load()
    }

    func start() {
        guard !started else { return }
        started = true
        authorization = monitorAuthorization()
        monitor.onEvent = { [weak self] event in
            let task = UIApplication.shared.beginBackgroundTask(withName: "daka.fence") {}
            Task { @MainActor in
                self?.handle(event)
                if task != .invalid {
                    UIApplication.shared.endBackgroundTask(task)
                }
            }
        }
        AlarmNotifier.registerCategories()
        AlarmFeedback.prepare()
        if remindersOn {
            monitor.requestAlways()
            monitor.startUpdating()
            syncRegions()
        }
        startWatching()
        refreshNotifications()
        Task { @MainActor in
            await absorbDeliveredArms()
            tickWindows()
        }
    }

    func setReminders(_ on: Bool) {
        remindersOn = on
        statusMessage = nil
        saveFlags()
        if on {
            monitor.requestAlways()
            monitor.startUpdating()
            syncRegions()
            tickWindows()
            refreshNotifications()
        } else {
            monitor.stopAll()
            stopAlarmPlayback()
            AlarmNotifier.cancelAll()
            clearArm(persist: true)
        }
    }

    func setArriveWindow(_ window: PunchWindow) {
        arriveWindow = window
        saveWindows()
        clearArm(persist: true)
        tickWindows()
    }

    func setLeaveWindow(_ window: PunchWindow) {
        leaveWindow = window
        saveWindows()
    }

    func upsert(_ place: Place) {
        if let index = places.firstIndex(where: { $0.id == place.id }) {
            places[index] = place
        } else {
            places.append(place)
        }
        places.sort { $0.updatedAt > $1.updatedAt }
        savePlaces()
        if remindersOn { syncRegions() }
    }

    func remove(id: UUID) {
        places.removeAll { $0.id == id }
        insideIds.remove(id.uuidString)
        savePlaces()
        saveFlags()
        refreshMembership()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        places[index].enabled = enabled
        places[index].updatedAt = Date()
        if !enabled { insideIds.remove(id.uuidString) }
        savePlaces()
        saveFlags()
        refreshMembership()
    }

    func beginLocating() {
        monitor.requestWhenInUse()
        monitor.startUpdating()
    }

    /// Continuous GPS is only for the on-screen distance. Region alarms keep running in the background.
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active {
            if authorization == .authorizedAlways || authorization == .authorizedWhenInUse || remindersOn {
                monitor.startUpdating()
            }
            Task { @MainActor in
                await absorbDeliveredArms()
                tickWindows()
            }
        } else if phase == .background {
            monitor.stopUpdating()
        }
    }

    func simulate(_ kind: ReminderKind) {
        guard let place = places.first(where: \.enabled) else { return }
        switch kind {
        case .arrive:
            insideIds.insert(place.id.uuidString)
            suppressArriveTickUntil = Date().addingTimeInterval(90)
        case .leave:
            insideIds.remove(place.id.uuidString)
        }
        saveFlags()
        ring(kind: kind, placeId: place.id, placeName: place.name, records: false)
    }

    /// Shows the alarm screen and starts the 30 second ring. Closing it does not confirm a punch.
    func presentAlarm(kind: ReminderKind, eventId: UUID?, placeName: String?) {
        ringingKind = kind
        ringingPlaceName = placeName
        ringingEventId = eventId
        AlarmFeedback.preview(kind: kind)
    }

    /// Stops the current ring and cancels its later repeats. The log stays unconfirmed.
    func dismissRing() {
        let eventId = ringingEventId
        stopAlarmPlayback()
        guard let eventId else { return }
        Task { await AlarmNotifier.cancel(eventId: eventId.uuidString) }
    }

    func deleteLog(id: UUID) {
        guard let index = logs.firstIndex(where: { $0.id == id }) else { return }
        let eventId = logs[index].eventId
        logs.remove(at: index)
        saveLogs()
        let wasArmed = armedEventId == eventId
        if ringingEventId == eventId {
            dismissRing()
        } else {
            Task { await AlarmNotifier.cancel(eventId: eventId.uuidString) }
        }
        if wasArmed {
            armedFireAt = nil
            armedEventId = nil
            armedPlaceId = nil
            saveFlags()
            tickWindows()
        }
    }

    func stopAlarmPlayback() {
        AlarmFeedback.stop()
        ringingKind = nil
        ringingPlaceName = nil
        ringingEventId = nil
    }

    func acknowledge(logId: UUID?, eventId: String?) {
        if let logId, let index = logs.firstIndex(where: { $0.id == logId }) {
            if logs[index].acknowledgedAt == nil {
                logs[index].acknowledgedAt = Date()
                saveLogs()
            }
            if logs.first?.id == logId || ringingEventId == logs[index].eventId {
                stopAlarmPlayback()
            }
            if logs[index].eventId == armedEventId {
                clearArm(persist: true)
                tickWindows()
            }
        }
        guard let eventId else { return }
        Task { await AlarmNotifier.cancel(eventId: eventId) }
    }

    /// Records the lock-screen arrive alarm once. Repeats of the same event still return true so they can ring again.
    func noteArmedArrive(userInfo: [AnyHashable: Any]) -> Bool {
        guard remindersOn else { return false }
        let eventId = (userInfo["eventId"] as? String).flatMap(UUID.init(uuidString:)) ?? armedEventId ?? UUID()
        if logs.contains(where: { $0.eventId == eventId }) {
            return true
        }
        if remindedToday(.arrive) {
            return false
        }
        markReminded(.arrive)
        let placeId = (userInfo["placeId"] as? String).flatMap(UUID.init(uuidString:)) ?? armedPlaceId ?? UUID()
        let placeName = userInfo["placeName"] as? String ?? "打卡范围"
        insertLog(kind: .arrive, placeId: placeId, placeName: placeName, eventId: eventId)
        return true
    }

    func snooze(userInfo: [AnyHashable: Any]) {
        if let eventId = userInfo["eventId"] as? String {
            Task { await AlarmNotifier.cancel(eventId: eventId) }
        }
        AlarmNotifier.snooze(userInfo: userInfo)
    }

    func handleNotification(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        let logId = (info["logId"] as? String).flatMap(UUID.init(uuidString:))
        let eventId = info["eventId"] as? String
        if response.actionIdentifier == AlarmNotifier.snoozeAction {
            snooze(userInfo: info)
            return
        }
        acknowledge(logId: logId, eventId: eventId)
    }

    var nearestEnabledPlace: Place? {
        let enabled = places.filter(\.enabled)
        guard let location else { return enabled.first }
        return enabled.min { $0.distance(from: location) < $1.distance(from: location) }
    }

    var containingPlace: Place? {
        guard let location else { return nil }
        return places.filter(\.enabled).filter { $0.contains(location) }.min {
            $0.distance(from: location) < $1.distance(from: location)
        }
    }

    private func handle(_ event: MonitorEvent) {
        switch event {
        case .authorization(let status):
            authorization = status
            if remindersOn, status == .authorizedAlways || status == .authorizedWhenInUse {
                syncRegions()
            }
        case .location(let location):
            guard accept(location) else { return }
            self.location = location
            if statusMessage?.contains("kCLErrorDomain") == true {
                statusMessage = nil
            }
            updateFence(from: location)
        case .entered(let id):
            handleEnter(id)
        case .exited(let id):
            handleExit(id, fromRegion: true)
        case .failed(let message):
            statusMessage = message
        }
    }

    private func handleEnter(_ id: String) {
        guard remindersOn, let place = places.first(where: { $0.id.uuidString == id && $0.enabled }) else { return }
        let inserted = insideIds.insert(id).inserted
        if inserted { saveFlags() }
        let now = Date()
        if inserted, arriveWindow.contains(now), !remindedToday(.arrive) {
            markReminded(.arrive)
            ring(kind: .arrive, placeId: place.id, placeName: place.name)
        }
        if inserted || !arriveWindow.contains(now) || remindedToday(.arrive) {
            scheduleArm(for: place, at: arriveWindow.nextOpening(after: now))
        }
    }

    /// A fresh precise fix replaces a coarse one. A sudden worse fix is ignored for a short while so Wi-Fi jitter does not move the center.
    private func accept(_ location: CLLocation) -> Bool {
        guard let current = self.location else { return true }
        let age = location.timestamp.timeIntervalSince(current.timestamp)
        if age >= 25 { return true }
        let precise = current.horizontalAccuracy >= 0 && current.horizontalAccuracy <= 40
        let muchWorse = location.horizontalAccuracy > current.horizontalAccuracy + 30
        if precise && muchWorse { return false }
        return true
    }

    /// Screen distance and region events both cross here. A fresh GPS fix inside the circle wins over a region exit.
    private func updateFence(from location: CLLocation) {
        guard remindersOn else { return }
        for place in places where place.enabled {
            let id = place.id.uuidString
            let distance = place.distance(from: location)
            if insideIds.contains(id) {
                if distance > place.radius + 40 {
                    handleExit(id)
                }
            } else if distance <= place.radius {
                handleEnter(id)
            }
        }
    }

    private func handleExit(_ id: String, fromRegion: Bool = false) {
        guard remindersOn, insideIds.contains(id) else { return }
        if fromRegion, freshGpsStillInside(id) { return }
        insideIds.remove(id)
        saveFlags()
        let place = places.first(where: { $0.id.uuidString == id })
        let now = Date()
        if leaveWindow.contains(now), !remindedToday(.leave) {
            markReminded(.leave)
            ring(kind: .leave, placeId: place?.id ?? UUID(), placeName: place?.name ?? "打卡范围")
        }
        if let stay = places.first(where: { $0.enabled && insideIds.contains($0.id.uuidString) }) {
            scheduleArm(for: stay, at: arriveWindow.nextOpening(after: now))
        } else {
            clearArm(persist: true)
        }
    }

    private func freshGpsStillInside(_ id: String) -> Bool {
        guard let location, location.timestamp.timeIntervalSinceNow > -15,
              let place = places.first(where: { $0.id.uuidString == id && $0.enabled }) else { return false }
        return place.distance(from: location) <= place.radius + 40
    }

    private func refreshNotifications() {
        Task {
            let allowed = await AlarmNotifier.requestAuthorization()
            rememberNotifications(allowed)
        }
    }

    private func rememberNotifications(_ allowed: Bool) {
        notificationsAllowed = allowed
        UserDefaults.standard.set(allowed, forKey: notificationsKey)
    }

    private func ring(kind: ReminderKind, placeId: UUID, placeName: String, records: Bool = true) {
        let eventId = UUID()
        let logId = records ? insertLog(kind: kind, placeId: placeId, placeName: placeName, eventId: eventId).id : nil
        let post = {
            AlarmNotifier.schedule(
                kind: kind,
                placeName: placeName,
                placeId: placeId,
                eventId: eventId,
                logId: logId,
                repeats: true
            )
        }
        if notificationsAllowed {
            post()
            return
        }
        let task = UIApplication.shared.beginBackgroundTask(withName: "daka.ring") {}
        Task {
            let allowed = await AlarmNotifier.requestAuthorization()
            rememberNotifications(allowed)
            guard remindersOn else {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
                return
            }
            if allowed {
                post()
            } else if UIApplication.shared.applicationState == .active {
                statusMessage = "通知权限没开，这次只在应用里响铃和震动。请到系统设置里允许通知。"
                presentAlarm(kind: kind, eventId: eventId, placeName: placeName)
            }
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
    }

    private func refreshMembership() {
        if remindersOn { syncRegions() }
        if places.contains(where: { $0.enabled && insideIds.contains($0.id.uuidString) }) {
            tickWindows()
        } else {
            clearArm(persist: true)
        }
    }

    private func syncRegions() {
        let enabled = places.filter(\.enabled).sorted { $0.updatedAt > $1.updatedAt }
        if enabled.count > 20 {
            statusMessage = "最多同时提醒 20 个范围，更早的已暂停。"
        }
        monitor.apply(places: Array(enabled.prefix(20)))
    }

    private func startWatching() {
        watchTask?.cancel()
        watchTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                tickWindows()
            }
        }
    }

    /// Rings arrive when the person is already inside as the window opens. Leave still waits for an exit.
    private func tickWindows() {
        guard remindersOn else { return }
        guard let place = placeConfirmedInside() else { return }
        let now = Date()
        let suppressed = (suppressArriveTickUntil ?? .distantPast) > now
        if arriveWindow.contains(now), !remindedToday(.arrive), !suppressed {
            markReminded(.arrive)
            clearArm(persist: true)
            ring(kind: .arrive, placeId: place.id, placeName: place.name)
        }
        scheduleArm(for: place, at: arriveWindow.nextOpening(after: now))
    }

    /// Region state plus a current fix. A simulated enter while GPS says outside does not arm a real alarm.
    private func placeConfirmedInside() -> Place? {
        let candidates = places.filter { $0.enabled && insideIds.contains($0.id.uuidString) }
        guard let location else { return candidates.first }
        return candidates.first { $0.distance(from: location) <= $0.radius + 40 }
    }

    private func scheduleArm(for place: Place, at start: Date) {
        if let armedFireAt {
            if abs(armedFireAt.timeIntervalSince(start)) < 1, armedPlaceId == place.id {
                return
            }
            let since = armedFireAt.timeIntervalSinceNow
            if since > -200, since < 5, start.timeIntervalSinceNow > 60 {
                return
            }
        }
        let eventId = UUID()
        armedEventId = eventId
        armedFireAt = start
        armedPlaceId = place.id
        saveFlags()
        AlarmNotifier.armArrive(at: start, placeId: place.id, placeName: place.name, eventId: eventId)
    }

    private func clearArm(persist: Bool) {
        armedFireAt = nil
        armedEventId = nil
        armedPlaceId = nil
        if persist { saveFlags() }
        AlarmNotifier.cancelArmedArrive()
    }

    private func absorbDeliveredArms() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        guard let note = delivered.first(where: { $0.request.identifier.hasPrefix(AlarmNotifier.armPrefix) }) else { return }
        _ = noteArmedArrive(userInfo: note.request.content.userInfo)
    }

    private func remindedToday(_ kind: ReminderKind) -> Bool {
        let today = dayKey()
        switch kind {
        case .arrive: return arriveRemindedDay == today
        case .leave: return leaveRemindedDay == today
        }
    }

    private func markReminded(_ kind: ReminderKind) {
        let today = dayKey()
        switch kind {
        case .arrive: arriveRemindedDay = today
        case .leave: leaveRemindedDay = today
        }
        saveFlags()
    }

    private func dayKey(_ date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    @discardableResult
    private func insertLog(kind: ReminderKind, placeId: UUID, placeName: String, eventId: UUID) -> ReminderLog {
        let log = ReminderLog(
            id: UUID(),
            eventId: eventId,
            placeId: placeId,
            placeName: placeName,
            kind: kind,
            at: Date(),
            acknowledgedAt: nil
        )
        logs.insert(log, at: 0)
        if logs.count > 200 { logs.removeLast(logs.count - 200) }
        saveLogs()
        return log
    }

    private func monitorAuthorization() -> CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let data = UserDefaults.standard.data(forKey: placesKey),
           let decoded = try? decoder.decode([Place].self, from: data) {
            places = decoded
        }
        if let data = UserDefaults.standard.data(forKey: logsKey),
           let decoded = try? decoder.decode([ReminderLog].self, from: data) {
            logs = decoded
        }
        remindersOn = UserDefaults.standard.bool(forKey: remindersKey)
        insideIds = Set(UserDefaults.standard.stringArray(forKey: insideKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: arriveWindowKey),
           let decoded = try? decoder.decode(PunchWindow.self, from: data) {
            arriveWindow = decoded
        }
        if let data = UserDefaults.standard.data(forKey: leaveWindowKey),
           let decoded = try? decoder.decode(PunchWindow.self, from: data) {
            leaveWindow = decoded
        }
        arriveRemindedDay = UserDefaults.standard.string(forKey: arriveDayKey)
        leaveRemindedDay = UserDefaults.standard.string(forKey: leaveDayKey)
        if let stamp = UserDefaults.standard.object(forKey: armedFireKey) as? Double {
            armedFireAt = Date(timeIntervalSince1970: stamp)
        }
        armedEventId = UserDefaults.standard.string(forKey: armedEventKey).flatMap(UUID.init(uuidString:))
        armedPlaceId = UserDefaults.standard.string(forKey: armedPlaceKey).flatMap(UUID.init(uuidString:))
        notificationsAllowed = UserDefaults.standard.bool(forKey: notificationsKey)
    }

    private func savePlaces() {
        persist(places, key: placesKey)
    }

    private func saveLogs() {
        persist(logs, key: logsKey)
    }

    private func saveWindows() {
        persist(arriveWindow, key: arriveWindowKey)
        persist(leaveWindow, key: leaveWindowKey)
    }

    private func saveFlags() {
        UserDefaults.standard.set(remindersOn, forKey: remindersKey)
        UserDefaults.standard.set(Array(insideIds), forKey: insideKey)
        UserDefaults.standard.set(arriveRemindedDay, forKey: arriveDayKey)
        UserDefaults.standard.set(leaveRemindedDay, forKey: leaveDayKey)
        if let armedFireAt {
            UserDefaults.standard.set(armedFireAt.timeIntervalSince1970, forKey: armedFireKey)
        } else {
            UserDefaults.standard.removeObject(forKey: armedFireKey)
        }
        UserDefaults.standard.set(armedEventId?.uuidString, forKey: armedEventKey)
        UserDefaults.standard.set(armedPlaceId?.uuidString, forKey: armedPlaceKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        if let data = try? encoder.encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
