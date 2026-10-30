import SwiftUI

struct CurrentLocationEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = "公司"
    @State private var radius = 150.0

    private let presets = RadiusLimit.presets

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(locationCopy)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    nameField
                    radiusControls
                    if let accuracy = model.location?.horizontalAccuracy, accuracy > 80 {
                        Text("这次定位偏差大约 ±\(Int(accuracy.rounded())) 米。到室外再取一次，圆心会更准。仍可以保存。")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    Button("保存范围") { save() }
                        .buttonStyle(PunchButtonStyle())
                        .disabled(model.location == nil)
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("当前位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .onAppear { model.beginLocating() }
        .presentationDetents([.medium, .large])
    }

    private var locationCopy: String {
        guard let location = model.location else {
            return "正在读取当前位置。请允许定位，并尽量站在平时打卡的地方。"
        }
        let accuracy = max(0, Int(location.horizontalAccuracy.rounded()))
        return "已取到当前位置，偏差约 ±\(accuracy) 米。下面的半径就是打卡范围。"
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("名称").font(.subheadline.weight(.medium))
            TextField("公司", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var radiusControls: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                            .background(radius == preset ? Theme.cinnabar : Theme.card, in: Capsule())
                            .foregroundStyle(radius == preset ? Theme.card : Theme.ink)
                    }
                }
            }
            Text("建议 150 到 300 米。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private func save() {
        guard let location = model.location else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = Place(
            id: UUID(),
            name: trimmed.isEmpty ? "公司" : String(trimmed.prefix(20)),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: radius,
            enabled: true,
            updatedAt: Date(),
            datum: Place.wgs84Datum
        )
        model.upsert(place)
        dismiss()
    }
}
