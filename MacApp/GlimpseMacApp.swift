import SwiftUI

@main
@MainActor
struct GlimpseMacApp: App {
    @State private var startup: Result<PhotoClassificationCoordinator, Error>

    init() {
        _startup = State(initialValue: Result {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("Glimpse/Native", isDirectory: true)
            let container = try PhotoClassificationTaskStore.nativeContainer(directory: directory)
            return PhotoClassificationCoordinator(container: container)
        })
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            switch startup {
            case .success(let coordinator):
                GlimpseMacRootView()
                    .environmentObject(coordinator)
                    .task { await coordinator.bootstrap() }
                    .frame(minWidth: 980, minHeight: 680)
            case .failure(let error):
                ContentUnavailableView {
                    Label("无法打开本机任务存储", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("\(error.localizedDescription)\n请检查目录权限和磁盘空间。不会自动删除或重建现有数据库。")
                }
                .frame(minWidth: 600, minHeight: 360)
            }
        }
        .defaultSize(width: 1180, height: 780)

        MenuBarExtra("Glimpse", systemImage: "photo.stack") {
            switch startup {
            case .success(let coordinator):
                GlimpseMenuBarView().environmentObject(coordinator)
            case .failure:
                Text("任务存储不可用")
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

private struct GlimpseMenuBarView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let identifier = coordinator.activeTaskID,
               let task = coordinator.tasks.first(where: { $0.id == identifier }) {
                Text(task.state == .paused ? "正在暂停，等待当前请求退出…" : "正在分类：\(task.title)")
                ProgressView(value: Double(task.progress.analyzed), total: Double(max(task.progress.total, 1)))
                if task.state == .running {
                    Button("暂停分类") { coordinator.pause(taskID: task.id) }
                }
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
