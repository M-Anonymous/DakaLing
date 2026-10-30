import CoreLocation
import Foundation

enum ReminderKind: String, Codable {
    case arrive
    case leave

    var title: String {
        switch self {
        case .arrive: "上班打卡"
        case .leave: "下班打卡"
        }
    }

    var soundFile: String {
        switch self {
        case .arrive: "arrive.wav"
        case .leave: "leave.wav"
        }
    }
}

struct Place: Codable, Identifiable, Equatable {
    static let wgs84Datum = "wgs84"

    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var enabled: Bool
    var updatedAt: Date
    /// Present when latitude/longitude are phone GPS coordinates. Older saves omit it.
    var datum: String?

    init(
        id: UUID,
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        enabled: Bool,
        updatedAt: Date,
        datum: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.enabled = enabled
        self.updatedAt = updatedAt
        self.datum = datum
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Pin position on the mainland map. Older saves stay where they were drawn.
    var mapCoordinate: CLLocationCoordinate2D {
        guard datum == Self.wgs84Datum else { return coordinate }
        return ChinaCoordinate.mapCoordinate(fromGPS: coordinate)
    }

    func distance(from location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    func contains(_ location: CLLocation) -> Bool {
        distance(from: location) <= radius
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, radius, enabled, updatedAt, datum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        radius = try container.decode(Double.self, forKey: .radius)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        datum = try container.decodeIfPresent(String.self, forKey: .datum)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(radius, forKey: .radius)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(datum, forKey: .datum)
    }
}

enum RadiusLimit {
    static let minimum = 100.0
    static let maximum = 800.0
    static let step = 10.0
    static let presets = [100.0, 150.0, 200.0, 300.0, 500.0]
}

struct ReminderLog: Codable, Identifiable, Equatable {
    var id: UUID
    var eventId: UUID
    var placeId: UUID
    var placeName: String
    var kind: ReminderKind
    var at: Date
    var acknowledgedAt: Date?
}

struct PunchWindow: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int

    static let arrive = PunchWindow(startMinutes: 9 * 60, endMinutes: 9 * 60 + 30)
    static let leave = PunchWindow(startMinutes: 20 * 60, endMinutes: 22 * 60)

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minutes = Self.minutes(from: date, calendar: calendar)
        if startMinutes <= endMinutes {
            return minutes >= startMinutes && minutes <= endMinutes
        }
        return minutes >= startMinutes || minutes <= endMinutes
    }

    /// The next time this window opens. Nil when `date` is already inside it.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        if contains(date, calendar: calendar) { return nil }
        return nextOpening(after: date, calendar: calendar)
    }

    /// The next opening strictly after `date`, even when `date` is already inside the window.
    func nextOpening(after date: Date, calendar: Calendar = .current) -> Date {
        let todayStart = Self.date(minutes: startMinutes, on: date, calendar: calendar)
        if todayStart > date { return todayStart }
        return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
    }

    var label: String {
        "\(Self.clock(startMinutes)) ～ \(Self.clock(endMinutes))"
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        parts.second = 0
        return calendar.date(from: parts) ?? day
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

enum MeterFormat {
    static func string(for meters: CLLocationDistance) -> String {
        guard meters.isFinite else { return "—" }
        let rounded = Int(meters.rounded())
        if rounded < 1000 { return "\(rounded) 米" }
        let kilometers = Double(rounded) / 1000
        if kilometers < 10 {
            let text = String(format: "%.1f", kilometers)
            let trimmed = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
            return "\(trimmed) 公里"
        }
        return "\(Int(kilometers.rounded())) 公里"
    }
}
