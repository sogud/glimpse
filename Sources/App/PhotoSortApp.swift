//
//  PhotoSortApp.swift
//  PhotoSort
//
//  Created by changshun on 2026/01/24.
//

import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

@main
struct PhotoSortApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 根视图 - 根据引导状态显示不同内容
struct RootView: View {
    @StateObject private var onboardingManager = OnboardingManager()
    
    var body: some View {
        Group {
            if onboardingManager.isOnboarding {
                OnboardingView()
                    .environmentObject(onboardingManager)
            } else {
                ContentView()
                    .environmentObject(onboardingManager)
            }
        }
    }
}

/// App 代理
#if canImport(UIKit)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 配置外观
        configureAppearance()
        return true
    }
    
    private func configureAppearance() {
        // 导航栏外观
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}
#endif
