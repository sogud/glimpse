import SwiftUI

enum MainAppTab: Hashable {
    case cleanup
    case smart
}

/// 新手引导之后的主应用壳，清理和智能分析互不抢状态。
struct MainTabView: View {
    @State private var selectedTab: MainAppTab = .cleanup
    @StateObject private var cleanupViewModel = PhotoSwipeViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(viewModel: cleanupViewModel)
                .tabItem {
                    Label("清理", systemImage: "rectangle.stack.badge.minus")
                }
                .tag(MainAppTab.cleanup)

            SmartAnalysisView { group in
                Task {
                    await cleanupViewModel.startSmartReviewSession(
                        title: group.title,
                        localIdentifiers: group.localIdentifiers
                    )
                    selectedTab = .cleanup
                }
            }
                .tabItem {
                    Label("智能", systemImage: "sparkles")
                }
                .tag(MainAppTab.smart)
        }
        .tint(.brandPrimary)
    }
}

#Preview {
    MainTabView()
        .environmentObject(OnboardingManager())
}
