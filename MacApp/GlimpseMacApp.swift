import SwiftUI

@main
struct GlimpseMacApp: App {
    @StateObject private var coordinator = PhotoClassificationCoordinator()

    var body: some Scene {
        WindowGroup(id: "main") {
            GlimpseMacRootView()
                .environmentObject(coordinator)
                .task { await coordinator.bootstrap() }
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 780)

        MenuBarExtra("Glimpse", systemImage: "photo.stack") {
            GlimpseMenuBarView()
                .environmentObject(coordinator)
        }
    }
}

private struct GlimpseMenuBarView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = coordinator.runningTask {
                Text("正在分类：\(task.title)")
                ProgressView(value: Double(task.results.count), total: Double(max(task.assetFingerprints.count, 1)))
            } else {
                Text("当前没有运行中的任务")
                    .foregroundStyle(.secondary)
            }
            Button("打开 Glimpse") { openWindow(id: "main") }
            Divider()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }
}
