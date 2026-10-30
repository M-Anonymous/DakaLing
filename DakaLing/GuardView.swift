import SwiftUI
import UIKit

struct GuardView: View {
    @Environment(AppModel.self) private var model
    @State private var showRemindersPrompt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        header(at: context.date)
                    }
                    statusCard
                    if let message = model.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Button(model.remindersOn ? "停止提醒" : "开启提醒") {
                        model.setReminders(!model.remindersOn)
                    }
                    .buttonStyle(PunchButtonStyle(filled: !model.remindersOn))

                    if model.places.contains(where: \.enabled) {
                        drill
                    }
                    guidance
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("叮当猫")
            .navigationBarTitleDisplayMode(.inline)
            .alert("请先开启提醒", isPresented: $showRemindersPrompt) {
                Button("开启提醒") { model.setReminders(true) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("模拟进入和模拟离开会一起响铃并震动。先把提醒打开，再点一次。")
            }
        }
    }

    private func header(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.cinnabar)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(model.containingPlace == nil ? Theme.ink : Theme.pine)
                    Text(now.formatted(.dateTime.month().day().weekday(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 10) {
                timeColumn("上班", window: model.arriveWindow, now: now)
                timeColumn("下班", window: model.leaveWindow, now: now)
            }
            Text(windowHint(at: now))
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeColumn(_ title: String, window: PunchWindow, now: Date) -> some View {
        let active = window.contains(now)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? Theme.cinnabar : Theme.muted)
            Text(window.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(active ? Theme.cinnabar : Theme.line, lineWidth: 1)
        }
    }

    private func windowHint(at now: Date) -> String {
        if model.arriveWindow.contains(now) {
            return "现在是上班时段。进入范围会提醒，人已经在里面也会提醒。今天的上班铃只响一次。"
        }
        if model.leaveWindow.contains(now) {
            return "现在是下班时段。离开范围会提醒下班，今天只响一次。"
        }
        return "现在不在打卡时段里。到了上班时段才会响上班铃，到了下班时段离开才会响下班铃。"
    }

    private var title: String {
        if model.places.filter(\.enabled).isEmpty { return "还没设范围" }
        if !model.remindersOn { return "提醒未开启" }
        if model.location == nil { return "正在定位" }
        if model.containingPlace != nil { return "在打卡范围内" }
        return "在打卡范围外"
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail)
                .font(.body)
                .foregroundStyle(Theme.ink)
            Text(permissionLine)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            if model.authorization == .denied || model.authorization == .restricted {
                Button("打开系统设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.footnote.weight(.medium))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1)
        }
    }

    private var detail: String {
        guard let place = model.containingPlace ?? model.nearestEnabledPlace else {
            return "到后台划定打卡范围。可以站在公司里直接取定位，也可以像地图一样选一个圆心。"
        }
        guard let location = model.location else {
            return "\(place.name)，半径 \(MeterFormat.string(for: place.radius))。正在等定位。"
        }
        let distance = MeterFormat.string(for: place.distance(from: location))
        guard location.horizontalAccuracy > 40 else {
            return "\(place.name) · 距圆心 \(distance)"
        }
        let accuracy = max(0, Int(location.horizontalAccuracy.rounded()))
        return "\(place.name) · 距圆心 \(distance)。这次定位偏差约 ±\(accuracy) 米，到室外会更准。"
    }

    private var permissionLine: String {
        switch model.authorization {
        case .authorizedAlways:
            "定位为「始终允许」。锁屏后进出范围也会响铃并震动。"
        case .authorizedWhenInUse:
            "目前只在使用期间定位。要锁屏提醒，请到系统设置里改成「始终」。"
        case .denied, .restricted:
            "定位被关掉了。提醒需要定位权限。"
        case .notDetermined:
            "点「开启提醒」后，定位请选「始终允许」，通知也要允许。"
        @unknown default:
            "请允许定位和通知。"
        }
    }

    private var drill: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("先试一次")
                .font(.headline)
            Text("不走路也能确认铃声和震动。模拟不受上下班时段限制，不会写进记录，也不会记成今天已经提醒过。模拟不会提交到公司的打卡系统。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                Button("模拟进入") { trySimulate(.arrive) }
                    .buttonStyle(PunchButtonStyle(filled: false))
                Button("模拟离开") { trySimulate(.leave) }
                    .buttonStyle(PunchButtonStyle(filled: false))
            }
        }
    }

    private func trySimulate(_ kind: ReminderKind) {
        if model.remindersOn {
            model.simulate(kind)
        } else {
            showRemindersPrompt = true
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("装在手机上之后")
                .font(.headline)
            Text("上班和离开都是铃声加震动，一起响 30 秒。响起后可以滑动关闭，也可以点「点击关闭」，这只停掉这一次。点「停止提醒」会马上全部停掉。锁屏或切到别的 App 也会提醒。从多任务界面把叮当猫划掉之后，要再打开一次，进出才会继续提醒。锁屏后通知铃声大约 29 秒，这是系统对自定义铃声的上限。请在「设置 → 声音与触感」里打开「响铃时震动」和「静音时震动」。时段可以在「后台」里改。公司打卡仍要在公司 App 里完成。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }
}
