import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView {
                GuardView()
                    .tabItem { Label("守护", systemImage: "cat.fill") }
                PlacesView()
                    .tabItem { Label("后台", systemImage: "pawprint.fill") }
                RadarView()
                    .tabItem { Label("雷达", systemImage: "dot.scope") }
                LogView()
                    .tabItem { Label("记录", systemImage: "book.fill") }
            }
            .background(Theme.paper)
            if let kind = model.ringingKind {
                AlarmCurtain(
                    kind: kind,
                    placeName: model.ringingPlaceName,
                    onDismiss: { model.dismissRing() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.ringingKind)
        .onAppear { model.start() }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
}
