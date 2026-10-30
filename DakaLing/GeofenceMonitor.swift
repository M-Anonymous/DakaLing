import CoreLocation
import Foundation

enum MonitorEvent {
    case authorization(CLAuthorizationStatus)
    case location(CLLocation)
    case entered(String)
    case exited(String)
    case failed(String)
}

final class GeofenceMonitor: NSObject, CLLocationManagerDelegate {
    var onEvent: ((MonitorEvent) -> Void)?

    private let manager: CLLocationManager
    private var askedForFullAccuracy = false

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
    }

    /// Continuous background GPS is only legal when Info.plist lists location as a background mode.
    /// Setting it otherwise trips a Core Location assertion and freezes the main thread.
    private static var canUseBackgroundLocation: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") == true
    }

    private func configureBackgroundUpdates(status: CLAuthorizationStatus) {
        let allowed = status == .authorizedAlways && Self.canUseBackgroundLocation
        manager.allowsBackgroundLocationUpdates = false
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.pausesLocationUpdatesAutomatically = false
        }
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    func startUpdating() {
        if manager.accuracyAuthorization == .reducedAccuracy, !askedForFullAccuracy {
            askedForFullAccuracy = true
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PunchFence")
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func apply(places: [Place]) {
        let limited = Array(places.filter(\.enabled).prefix(20))
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        for place in limited {
            let region = CLCircularRegion(
                center: place.coordinate,
                radius: max(place.radius, 1),
                identifier: place.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }
    }

    func stopAll() {
        manager.stopUpdatingLocation()
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        configureBackgroundUpdates(status: status)
        onEvent?(.authorization(status))
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            startUpdating()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0 else { return }
        guard location.timestamp.timeIntervalSinceNow > -20 else { return }
        onEvent?(.location(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Code 0 is kCLErrorLocationUnknown. Core Location keeps trying, so it is not a failure.
        if (error as? CLError)?.code == .locationUnknown { return }
        onEvent?(.failed(Self.locationFailureMessage(error)))
    }

    private static func locationFailureMessage(_ error: Error) -> String {
        switch (error as? CLError)?.code {
        case .denied:
            return "定位被关掉了。请到系统设置里允许「始终」。"
        case .network:
            return "定位需要网络，当前网络不可用。"
        default:
            return "定位暂时不可用，会继续重试。"
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        onEvent?(.entered(region.identifier))
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        onEvent?(.exited(region.identifier))
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        switch state {
        case .inside:
            onEvent?(.entered(region.identifier))
        case .outside:
            onEvent?(.exited(region.identifier))
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        onEvent?(.failed("范围提醒没有启动：\(error.localizedDescription)"))
    }
}
