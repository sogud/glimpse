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
    
    // MARK: - Private
    
    private enum Keys {
        static let onboardingCompleted = "onboarding_completed"
    }
}
