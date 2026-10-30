import SwiftUI

struct PlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var gpsEditor = false
    @State private var mapRoute: MapRoute?
    @State private var pendingDelete: Place?
    @State private var timeExpanded = false
    @State private var placeExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("时段和定位分开收着。点标题就能展开。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)

                    FoldSection(
                        title: "打卡时段",
                        symbol: "cat.fill",
                        summary: "上班 \(model.arriveWindow.label)\n下班 \(model.leaveWindow.label)",
                        expanded: $timeExpanded
                    ) {
                        windowFields
                    }

                    FoldSection(
                        title: "打卡定位",
                        symbol: "pawprint.fill",
                        summary: placeSummary,
                        expanded: $placeExpanded
                    ) {
                        placeFields
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("后台")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $gpsEditor) {
                CurrentLocationEditor()
            }
            .fullScreenCover(item: $mapRoute) { route in
                MapPickView(existing: route.place)
            }
            .confirmationDialog(
                "删除这个范围？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let pendingDelete { model.remove(id: pendingDelete.id) }
                    pendingDelete = nil
                }
                Button("留下", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("删除后不再对这个地点响铃。已经记下的记录还会留着。")
            }
        }
    }

    private var placeSummary: String {
        if model.places.isEmpty { return "还没设范围" }
        let enabled = model.places.filter(\.enabled).count
        return "\(model.places.count) 个范围，\(enabled) 个在用"
    }

    private var windowFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("上班铃只在上班时段里响，下班铃只在下班时段里响。每个时段每天最多一次。人已经在公司里、上班时段才开始，也会响。离开公司才响下班铃。模拟进入和模拟离开不受时段限制，也不会写进记录，但要先开启提醒。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            windowRow("上班", window: model.arriveWindow) { model.setArriveWindow($0) }
            windowRow("下班", window: model.leaveWindow) { model.setLeaveWindow($0) }
        }
    }

    private func windowRow(_ title: String, window: PunchWindow, set: @escaping (PunchWindow) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.cinnabar)
            HStack(spacing: 12) {
                labeledTime("开始", minutes: window.startMinutes) { minutes in
                    var next = window
                    next.startMinutes = minutes
                    set(next)
                }
                labeledTime("结束", minutes: window.endMinutes) { minutes in
                    var next = window
                    next.endMinutes = minutes
                    set(next)
                }
            }
            if window.endMinutes < window.startMinutes {
                Text("\(title)时段会跨过午夜。")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func labeledTime(_ title: String, minutes: Int, set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            DatePicker(
                title,
                selection: Binding(
                    get: { PunchWindow.date(minutes: minutes, on: Date()) },
                    set: { set(PunchWindow.minutes(from: $0)) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("人可以站在打卡的位置直接取圆心，也可以像地图一样搜索、拖动，把针尖对准地点，再拉半径。蓝点是当前定位，保存时会和手机定位对齐。以前设过的范围，打开地图确认针尖还在公司，再保存一次。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Button("使用当前位置") { gpsEditor = true }
                .buttonStyle(PunchButtonStyle())
            Button("在地图上选点") { mapRoute = MapRoute(place: nil) }
                .buttonStyle(PunchButtonStyle(filled: false))
            if model.places.isEmpty {
                Text("还没有范围。上面两种方式都可以设第一个。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(model.places) { place in
                placeCard(place)
            }
        }
    }

    private func placeCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(place.name).font(.headline)
                Spacer()
                Toggle(
                    "启用",
                    isOn: Binding(
                        get: { place.enabled },
                        set: { model.setEnabled($0, id: place.id) }
                    )
                )
                .labelsHidden()
                .tint(Theme.cinnabar)
            }
            Text("半径 \(MeterFormat.string(for: place.radius))\(place.enabled ? "" : " · 已停用")")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Text(String(format: "%.5f，%.5f", place.latitude, place.longitude))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                Button("在地图上调整") { mapRoute = MapRoute(place: place) }
                    .buttonStyle(PunchButtonStyle(filled: false))
                Button("删除") { pendingDelete = place }
                    .buttonStyle(PunchButtonStyle(filled: false))
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1)
        }
    }
}

private struct FoldSection<Content: View>: View {
    let title: String
    let symbol: String
    let summary: String
    @Binding var expanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.cinnabar)
                        .frame(width: 36, height: 36)
                        .background(Theme.line.opacity(0.65), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.cinnabar)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: expanded)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            .accessibilityHint(summary)

            if expanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        }
        .geometryGroup()
    }
}

struct MapRoute: Identifiable {
    let id = UUID()
    let place: Place?
}
