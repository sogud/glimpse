//
//  HapticService.swift
//  PhotoSwipeCleaner
//
//  触觉反馈服务
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 触觉反馈服务
class HapticService {
    
    static let shared = HapticService()
    
    private init() {}
    
    // MARK: - 通知类型反馈
    
    /// 成功反馈
    func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
    
    /// 警告反馈
    func warning() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
    
    /// 错误反馈
    func error() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }
    
    // MARK: - 冲击类型反馈
    
    /// 轻触反馈
    func light() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
    
    /// 中等反馈
    func medium() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
    
    /// 重反馈
    func heavy() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        #endif
    }
    
    /// 软反馈
    func soft() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
        #endif
    }
    
    /// 刚性反馈
    func rigid() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        #endif
    }
    
    // MARK: - 选择反馈
    
    /// 选择变化反馈
    func selection() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
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
        #if canImport(UIKit)
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
        #endif
    }
}
