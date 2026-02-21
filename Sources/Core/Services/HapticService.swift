//
//  HapticService.swift
//  PhotoSwipeCleaner
//
//  触觉反馈服务
//

import UIKit

/// 触觉反馈服务
class HapticService {
    
    static let shared = HapticService()
    
    private init() {}
    
    // MARK: - 通知类型反馈
    
    /// 成功反馈
    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    /// 警告反馈
    func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    /// 错误反馈
    func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    // MARK: - 冲击类型反馈
    
    /// 轻触反馈
    func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    /// 中等反馈
    func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    /// 重反馈
    func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    /// 软反馈
    func soft() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }
    
    /// 刚性反馈
    func rigid() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }
    
    // MARK: - 选择反馈
    
    /// 选择变化反馈
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    // MARK: - 场景化反馈
    
    /// 滑动保留反馈
    func swipeKeep() {
        light()
    }
    
    /// 滑动删除反馈
    func swipeDelete() {
        heavy()
    }
    
    /// 滑动归档反馈
    func swipeArchive() {
        medium()
    }
    
    /// 滑动跳过反馈
    func swipeSkip() {
        soft()
    }
    
    /// 步骤完成反馈
    func stepComplete() {
        success()
    }
    
    /// 引导完成庆祝反馈
    func celebration() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 连续震动效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
    }
}
