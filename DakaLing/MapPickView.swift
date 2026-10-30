import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct MapPickView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let existing: Place?
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var radius: Double
    @State private var name: String
    @State private var query = ""
    @State private var address = ""
    @StateObject private var search = PlaceSearch()
    @State private var geocodeTask: Task<Void, Never>?
    @State private var keyboardOverlap: CGFloat = 0
    @FocusState private var focus: MapField?

    private let presets = RadiusLimit.presets

    init(existing: Place?) {
        self.existing = existing
        let fallback = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        let coordinate = existing?.mapCoordinate ?? ChinaCoordinate.mapCoordinate(fromGPS: fallback)
        _center = State(initialValue: coordinate)
        let stored = existing?.radius ?? 150
        _radius = State(initialValue: min(RadiusLimit.maximum, max(RadiusLimit.minimum, stored)))
        _name = State(initialValue: existing?.name ?? "公司")
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 900,
            longitudinalMeters: 900
        )))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                controls
            }
            .padding(.bottom, focus == .name ? keyboardOverlap : 0)
            .background(Theme.paper)
            .ignoresSafeArea(.keyboard)
            .navigationTitle(existing == nil ? "地图选点" : "调整范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                updateKeyboard(note)
            }
        }
        .onAppear(perform: centerOnUserIfNeeded)
    }

    private var map: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                UserAnnotation()
                MapCircle(center: center, radius: radius)
                    .foregroundStyle(Theme.cinnabar.opacity(0.22))
            }
            .ignoresSafeArea(.keyboard)
            .mapStyle(.standard(elevation: .flat))
            .onMapCameraChange(frequency: .continuous) { context in
                center = context.camera.centerCoordinate
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                scheduleGeocode(context.camera.centerCoordinate)
            }

            Image(systemName: "mappin")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Theme.cinnabar)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .offset(y: -16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                TextField("搜索地点，例如公司、园区、地铁站", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .focused($focus, equals: .search)
                    .onSubmit { search.update(query: query, around: center) }
                    .onChange(of: query) { _, newValue in
                        search.update(query: newValue, around: center)
                    }
                if !query.isEmpty && !search.results.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(search.results.prefix(5).enumerated()), id: \.offset) { _, result in
                                Button {
                                    select(result)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title).foregroundStyle(Theme.ink)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle).font(.caption).foregroundStyle(Theme.muted)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .padding(.horizontal, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(12)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        centerOnUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.cinnabar)
                            .frame(width: 44, height: 44)
                            .background(Theme.card, in: Circle())
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(address.isEmpty ? "拖动地图，把针尖对准打卡地点" : address)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
            Text(accuracyLine)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .lineLimit(3)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .name)
            Text("半径 \(MeterFormat.string(for: radius))")
                .font(.subheadline.weight(.medium))
            Slider(value: $radius, in: RadiusLimit.minimum...RadiusLimit.maximum, step: RadiusLimit.step)
                .tint(Theme.cinnabar)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button("\(Int(preset)) 米") { radius = preset }
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(radius == preset ? Theme.cinnabar : Theme.paper, in: Capsule())
                            .foregroundStyle(radius == preset ? Theme.card : Theme.ink)
                    }
                }
            }
            Button("保存范围") { save() }
                .buttonStyle(PunchButtonStyle())
        }
        .padding(16)
        .background(Theme.card)
    }

    private func centerOnUserIfNeeded() {
        model.beginLocating()
        guard existing == nil, let location = model.location else { return }
        move(to: ChinaCoordinate.mapCoordinate(fromGPS: location.coordinate))
    }

    private func centerOnUser() {
        model.beginLocating()
        guard let location = model.location else { return }
        move(to: ChinaCoordinate.mapCoordinate(fromGPS: location.coordinate))
    }

    private var accuracyLine: String {
        guard let accuracy = model.location?.horizontalAccuracy, accuracy >= 0 else {
            return "蓝点是当前定位。国内地图和手机定位会差一截，保存时会对齐。"
        }
        let meters = max(0, Int(accuracy.rounded()))
        if existing?.datum != Place.wgs84Datum && existing != nil {
            return "蓝点偏差约 ±\(meters) 米。看针尖是否还在公司，不在就拖过去，再保存一次。"
        }
        if meters > 40 {
            return "蓝点偏差约 ±\(meters) 米。到室外空地会更准，再把针尖对准打卡地点。"
        }
        return "蓝点是当前定位，偏差约 ±\(meters) 米。把针尖对准打卡地点后再保存。"
    }

    private func move(to coordinate: CLLocationCoordinate2D) {
        center = coordinate
        position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
        scheduleGeocode(coordinate)
    }

    private func updateKeyboard(_ note: Notification) {
        guard focus == .name else { return }
        let overlap = keyboardOverlapHeight(from: note)
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardOverlap = overlap
        }
    }

    private func keyboardOverlapHeight(from note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let bounds = scene?.screen.bounds ?? frame
        return max(0, bounds.intersection(frame).height)
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        focus = nil
        query = completion.title
        search.results = []
        let request = MKLocalSearch.Request(completion: completion)
        Task {
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return }
            await MainActor.run {
                if name == "公司" || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = item.name ?? name
                }
                move(to: item.placemark.coordinate)
            }
        }
    }

    private func scheduleGeocode(_ coordinate: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let gps = ChinaCoordinate.gpsCoordinate(fromMap: coordinate)
            let location = CLLocation(latitude: gps.latitude, longitude: gps.longitude)
            let geocoder = CLGeocoder()
            let placemark = try? await geocoder.reverseGeocodeLocation(location).first
            guard !Task.isCancelled else { return }
            let text = [placemark?.name, placemark?.locality].compactMap { $0 }.joined(separator: " · ")
            await MainActor.run {
                address = text
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let gps = ChinaCoordinate.gpsCoordinate(fromMap: center)
        let place = Place(
            id: existing?.id ?? UUID(),
            name: trimmed.isEmpty ? "公司" : String(trimmed.prefix(20)),
            latitude: gps.latitude,
            longitude: gps.longitude,
            radius: radius,
            enabled: existing?.enabled ?? true,
            updatedAt: Date(),
            datum: Place.wgs84Datum
        )
        model.upsert(place)
        dismiss()
    }
}

private enum MapField: Hashable {
    case search
    case name
}

final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, around center: CLLocationCoordinate2D) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        completer.region = MKCoordinateRegion(center: center, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
