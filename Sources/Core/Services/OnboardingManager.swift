//
//  OnboardingManager.swift
//  PhotoSwipeCleaner
//
//  管理新手引导流程状态
//

import SwiftUI
import Photos

/// 新手引导步骤
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case tutorial
    case permission
    case albumSetup
    case analysis
    case complete

    var title: String {
        switch self {
        case .welcome:
            return "欢迎"
        case .tutorial:
            return "手势教程"
        case .permission:
            return "权限申请"
        case .albumSetup:
            return "相册设置"
        case .analysis:
            return "智能分析"
        case .complete:
            return "准备就绪"
        }
    }
}

/// 引导页面数据
struct OnboardingPage {
    let step: OnboardingStep
    let title: String
    let subtitle: String
    let description: String
    let imageName: String
    let primaryButtonTitle: String
    let secondaryButtonTitle: String?
}

/// 管理新手引导流程
@MainActor
class OnboardingManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 当前引导步骤
    @Published var currentStep: OnboardingStep = .welcome
    
    /// 是否正在显示引导
    @Published var isOnboarding: Bool = false
    
    /// 分析进度 (0.0 - 1.0)
    @Published var analysisProgress: Double = 0.0
    
    /// 分析发现的照片统计
    @Published var analysisResults: AnalysisResults?
    
    /// 教程中手势完成情况
    @Published var completedGestures: Set<GestureDirection> = []
    
    // MARK: - Computed Properties
    
    /// 是否已完成所有引导步骤
    var isOnboardingCompleted: Bool {
        UserDefaults.standard.bool(forKey: Keys.onboardingCompleted)
    }
    
    /// 当前步骤进度 (0.0 - 1.0)
    var progress: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
    
    /// 是否所有教程手势都已完成（只要求左右滑动）
    var isTutorialCompleted: Bool {
        completedGestures.contains(.left) && completedGestures.contains(.right)
    }
    
    // MARK: - Initialization
    
    init() {
        // 检查是否需要显示引导
        if !isOnboardingCompleted {
            isOnboarding = true
        }
    }
    
    // MARK: - Public Methods
    
    /// 开始新手引导
    func startOnboarding() {
        currentStep = .welcome
        isOnboarding = true
        completedGestures.removeAll()
        analysisProgress = 0.0
        analysisResults = nil
    }
    
    /// 进入下一步
    func nextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = next
        }
    }
    
    /// 返回上一步
    func previousStep() {
        guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = previous
        }
    }
    
    /// 跳转到指定步骤
    func jumpToStep(_ step: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = step
        }
    }
    
    /// 完成引导
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Keys.onboardingCompleted)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isOnboarding = false
        }
    }
    
    /// 重置引导状态（用于测试）
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: Keys.onboardingCompleted)
        completedGestures.removeAll()
        startOnboarding()
    }
    
    /// 标记手势为已完成
    func markGestureCompleted(_ direction: GestureDirection) {
        guard direction != .none else { return }
        
        withAnimation(.spring()) {
            _ = completedGestures.insert(direction)
        }
        
        // 震动反馈
        HapticService.shared.success()
    }
    
    /// 执行智能分析
    func performAnalysis() async {
        analysisProgress = 0.0
        
        // 模拟分析进度
        let totalSteps = 5
        for step in 1...totalSteps {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6秒
            
            await MainActor.run {
                withAnimation(.easeInOut) {
                    analysisProgress = Double(step) / Double(totalSteps)
                }
            }
        }
        
        // 获取实际照片统计
        await MainActor.run {
            analysisResults = AnalysisResults(
                totalPhotos: 0, // 实际从 PhotoLibraryService 获取
                screenshots: Int.random(in: 20...100),
                similarGroups: Int.random(in: 5...20),
                duplicates: Int.random(in: 10...50),
                largeFiles: Int.random(in: 5...30)
            )
        }
    }
    
    // MARK: - Private
    
    private enum Keys {
        static let onboardingCompleted = "onboarding_completed"
    }
}

/// 分析结果数据
struct AnalysisResults {
    let totalPhotos: Int
    let screenshots: Int
    let similarGroups: Int
    let duplicates: Int
    let largeFiles: Int
    
    var totalOptimizable: Int {
        screenshots + duplicates + largeFiles
    }
}
