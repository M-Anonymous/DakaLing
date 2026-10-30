import SwiftUI

struct AlarmCurtain: View {
    let kind: ReminderKind
    let placeName: String?
    let onDismiss: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var closed = false

    private let knob: CGFloat = 64

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.82, blue: 0.84),
                    Theme.paper,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 24)
                Image(systemName: "cat.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.cinnabar)
                Text(kind.title)
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Theme.ink)
                if let placeName, !placeName.isEmpty {
                    Text(placeName)
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                }
                Text("滑动到底，或点下面关掉。这只停掉这一次铃声和后面的重复，不会记成已经打卡。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer(minLength: 24)
                slideTrack
                Button("点击关闭", action: close)
                    .buttonStyle(PunchButtonStyle())
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }
        }
    }

    private var slideTrack: some View {
        GeometryReader { geo in
            let maxX = max(0, geo.size.width - knob - 8)
            let fillWidth = min(geo.size.width, 4 + dragX + knob)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.card)
                Capsule()
                    .fill(Theme.cinnabar)
                    .frame(width: fillWidth)
                Text("滑动关闭")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text("滑动关闭")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.card)
                            .frame(maxWidth: .infinity)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: fillWidth, height: knob)
                            }
                    }
                    .allowsHitTesting(false)
                Circle()
                    .fill(Theme.cinnabar)
                    .frame(width: knob, height: knob)
                    .overlay {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.card)
                    }
                    .offset(x: 4 + dragX)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard !closed else { return }
                                dragX = min(max(0, value.translation.width), maxX)
                            }
                            .onEnded { _ in
                                guard !closed else { return }
                                if maxX > 0, dragX >= maxX * 0.85 {
                                    close()
                                } else {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragX = 0
                                    }
                                }
                            }
                    )
                    .accessibilityLabel("滑动关闭")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, close)
            }
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(Theme.line, lineWidth: 1)
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 28)
    }

    private func close() {
        guard !closed else { return }
        closed = true
        onDismiss()
    }
}
