import CoreLocation
import SwiftUI

struct RadarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    radarCard
                    Text("圆心画在中间，粉点是你现在的位置，上方是北。人一动，粉点就跟着动。")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("雷达")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { model.beginLocating() }
    }

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headline)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            radar
                .frame(maxWidth: .infinity)
            HStack(spacing: 16) {
                legend(color: Theme.ink, title: "圆心")
                legend(color: userColor, title: "我")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        }
    }

    private var radar: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    radarDisc(side: side)
                        .frame(width: side, height: side)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
    }

    private func radarDisc(side: CGFloat) -> some View {
        let plot = currentPlot
        return ZStack {
            Circle()
                .fill(Theme.paper)
            Circle()
                .stroke(Theme.line, lineWidth: 1)
            rings
            compassMarks
            if let plot {
                Circle()
                    .stroke(Theme.cinnabar.opacity(0.85), lineWidth: 1.5)
                    .padding(side * (1 - plot.ring) / 2)
                userMark(plot: plot, side: side)
            }
            crosshair
        }
        .clipShape(Circle())
    }

    private var rings: some View {
        ZStack {
            ForEach([0.33, 0.66], id: \.self) { scale in
                Circle()
                    .stroke(Theme.line.opacity(0.9), lineWidth: 1)
                    .scaleEffect(scale)
            }
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
        }
        .allowsHitTesting(false)
    }

    private var compassMarks: some View {
        ZStack {
            mark("北", alignment: .top)
            mark("东", alignment: .trailing)
            mark("南", alignment: .bottom)
            mark("西", alignment: .leading)
        }
        .padding(8)
        .allowsHitTesting(false)
    }

    private func mark(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var crosshair: some View {
        ZStack {
            Circle()
                .fill(Theme.card)
                .frame(width: 10, height: 10)
            Circle()
                .stroke(Theme.ink, lineWidth: 2)
                .frame(width: 10, height: 10)
        }
        .allowsHitTesting(false)
    }

    private func userMark(plot: RadarPlot, side: CGFloat) -> some View {
        let reach = min(plot.user, 0.9) * side / 2
        let radians = plot.bearing * .pi / 180
        let x = sin(radians) * reach
        let y = -cos(radians) * reach
        return ZStack {
            if let halo = plot.halo {
                Circle()
                    .stroke(userColor.opacity(0.35), lineWidth: 1)
                    .frame(width: min(side * halo, side * 0.9), height: min(side * halo, side * 0.9))
            }
            Circle()
                .fill(userColor)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle().stroke(Theme.card, lineWidth: 2)
                }
            if let course = plot.course {
                Image(systemName: "location.north.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.card)
                    .rotationEffect(.degrees(course))
            }
        }
        .offset(x: x, y: y)
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private var headline: String {
        guard let place = focusPlace else { return "还没有圆心" }
        guard let location = model.location else { return place.name }
        return place.contains(location) ? "在范围内" : "在范围外"
    }

    private var summary: String {
        guard let place = focusPlace else {
            return "到后台划一个打卡范围，雷达才知道圆心在哪。"
        }
        guard let location = model.location else {
            return "\(place.name)，半径 \(MeterFormat.string(for: place.radius))。正在等定位。"
        }
        let distance = MeterFormat.string(for: place.distance(from: location))
        if location.horizontalAccuracy > 40 {
            let accuracy = max(0, Int(location.horizontalAccuracy.rounded()))
            return "\(place.name) · 距圆心 \(distance)。偏差约 ±\(accuracy) 米。"
        }
        return "\(place.name) · 距圆心 \(distance)。半径 \(MeterFormat.string(for: place.radius))。"
    }

    private var userColor: Color {
        guard let place = focusPlace, let location = model.location else { return Theme.cinnabar }
        return place.contains(location) ? Theme.pine : Theme.cinnabar
    }

    private var focusPlace: Place? {
        model.containingPlace ?? model.nearestEnabledPlace
    }

    private var currentPlot: RadarPlot? {
        guard let place = focusPlace, let location = model.location else { return nil }
        let distance = place.distance(from: location)
        let span = max(place.radius, distance, 40) * 1.35
        let course = location.speed > 0.5 && location.course >= 0 ? location.course : nil
        let accuracy = location.horizontalAccuracy
        let halo = accuracy > 0 && accuracy < span ? CGFloat(accuracy / span) : nil
        return RadarPlot(
            distance: distance,
            bearing: bearing(from: place.coordinate, to: location.coordinate),
            ring: CGFloat(place.radius / span),
            user: CGFloat(distance / span),
            halo: halo,
            course: course
        )
    }

    private func bearing(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let delta = (target.longitude - origin.longitude) * .pi / 180
        let y = sin(delta) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

private struct RadarPlot: Equatable {
    var distance: Double
    var bearing: Double
    var ring: CGFloat
    var user: CGFloat
    var halo: CGFloat?
    var course: Double?
}
