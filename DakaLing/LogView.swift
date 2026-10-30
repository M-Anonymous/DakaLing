import SwiftUI

struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.logs.isEmpty {
                    Text("还没有提醒。进出范围之后，上班和下班记录会出现在这里。没确认的可以点确认，不需要的可以左滑删除。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    List {
                        ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                            Section(dayLabel(day)) {
                                ForEach(grouped[day] ?? []) { entry in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("\(entry.kind.title) · \(entry.placeName)")
                                                    .font(.subheadline.weight(.medium))
                                                Text(entry.at.formatted(date: .omitted, time: .shortened))
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(Theme.muted)
                                            }
                                            Spacer()
                                            Text(entry.acknowledgedAt == nil ? "未确认" : "已确认")
                                                .font(.caption.weight(.medium))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(entry.acknowledgedAt == nil ? Theme.cinnabar : Theme.line, in: Capsule())
                                                .foregroundStyle(entry.acknowledgedAt == nil ? Theme.card : Theme.ink)
                                        }
                                        if entry.acknowledgedAt == nil {
                                            Button(entry.kind == .arrive ? "确认上班打卡" : "确认下班打卡") {
                                                model.acknowledge(logId: entry.id, eventId: entry.eventId.uuidString)
                                            }
                                            .buttonStyle(PunchButtonStyle())
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button("删除", role: .destructive) {
                                            model.deleteLog(id: entry.id)
                                        }
                                    }
                                    .listRowBackground(Theme.card)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .safeAreaInset(edge: .bottom) {
                        Text("这里的确认会停掉这次铃声，并记在手机上。左滑一条记录可以删掉。公司系统里的定位打卡，还是要在公司 App 里完成。")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.paper)
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var grouped: [String: [ReminderLog]] {
        Dictionary(grouping: model.logs) { entry in
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: entry.at)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }

    private func dayLabel(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
