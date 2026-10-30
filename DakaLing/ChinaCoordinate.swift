import CoreLocation
import Foundation

/// Apple Maps in mainland China draws GCJ-02, while Core Location reports WGS-84.
/// The two differ by a few hundred meters. Map pins use the map coordinate;
/// saved places and geofences use the GPS coordinate.
enum ChinaCoordinate {
    static func mapCoordinate(fromGPS gps: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(gps) else { return gps }
        let (latitude, longitude) = gcj02(latitude: gps.latitude, longitude: gps.longitude)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func gpsCoordinate(fromMap map: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(map) else { return map }
        var latitude = map.latitude
        var longitude = map.longitude
        for _ in 0..<8 {
            let projected = gcj02(latitude: latitude, longitude: longitude)
            latitude += map.latitude - projected.latitude
            longitude += map.longitude - projected.longitude
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        if longitude < 72.004 || longitude > 137.8347 { return false }
        if latitude < 0.8293 || latitude > 55.8271 { return false }
        return true
    }

    private static func gcj02(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        let a = 6_378_245.0
        let ee = 0.00669342162296594323
        var dLat = transformLatitude(longitude - 105.0, latitude - 35.0)
        var dLon = transformLongitude(longitude - 105.0, latitude - 35.0)
        let radLat = latitude / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * Double.pi)
        return (latitude + dLat, longitude + dLon)
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var value = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        value += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        value += (160.0 * sin(y / 12.0 * Double.pi) + 320 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return value
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var value = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        value += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        value += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return value
    }
}
