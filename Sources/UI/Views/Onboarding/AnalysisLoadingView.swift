//
//  AnalysisLoadingView.swift
//  PhotoSwipeCleaner
//
//  智能分析加载页面 - 玻璃拟态设计
//

import SwiftUI

/// 智能分析加载页面
struct AnalysisLoadingView: View {
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentAnalyzingText = "正在扫描相册..."

    private let analyzingTexts = [
        "正在扫描相册...",
        "正在识别截图...",
        "正在查找相似照片...",
        "正在分析大文件...",
        "分析完成！"
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // 动画图标
            analysisAnimation

            // 进度条
            progressSection

            // 分析状态
            statusSection

            Spacer()

            // 结果展示（分析完成后）
            if let results = onboardingManager.analysisResults {
                resultsView(results)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding()
        .onAppear {
            startAnalysis()
        }
    }

    // MARK: - Subviews

    private var analysisAnimation: some View {
        ZStack {
            // 外圈脉冲 - 柔和
            Circle()
                .stroke(Color.brandPrimary.opacity(0.15), lineWidth: 1.5)
                .frame(width: 160, height: 160)
                .scaleEffect(1 + CGFloat(sin(Date().timeIntervalSince1970 * 3)) * 0.05)

            // 中圈
            Circle()
                .fill(Color.brandPrimary.opacity(0.08))
                .frame(width: 140, height: 140)

            // 内圈 - 玻璃拟态
            Circle()
                .fill(LinearGradient.glass)
                .frame(width: 120, height: 120)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            // 图标
            Image(systemName: onboardingManager.analysisResults != nil ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 50, weight: .medium))
                .foregroundColor(onboardingManager.analysisResults != nil ? .swipeKeep : .brandPrimary)
                .symbolEffect(.bounce, options: .repeating, value: onboardingManager.analysisProgress)
        }
        .frame(height: 200)
    }

    private var progressSection: some View {
        VStack(spacing: 12) {
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 8)

                    // 进度 - 柔和渐变
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient.brand)
                        .frame(width: geometry.size.width * CGFloat(onboardingManager.analysisProgress), height: 8)
                        .animation(.easeInOut(duration: 0.3), value: onboardingManager.analysisProgress)
                }
            }
            .frame(height: 8)

            // 百分比
            Text("\(Int(onboardingManager.analysisProgress * 100))%")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: 280)
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            Text(currentAnalyzingText)
                .font(.headline)
                .foregroundColor(.primary)

            if onboardingManager.analysisResults == nil {
                Text("这可能需要几秒钟")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: onboardingManager.analysisProgress) { oldProgress, newProgress in
            updateAnalyzingText(for: newProgress)
        }
    }

    private func resultsView(_ results: AnalysisResults) -> some View {
        VStack(spacing: 20) {
            Text("发现可优化照片")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                resultCard(
                    icon: "crop",
                    title: "截图",
                    count: results.screenshots,
                    color: .swipeSkip
                )

                resultCard(
                    icon: "square.grid.2x2",
                    title: "相似照片",
                    count: results.similarGroups,
                    subtitle: "组",
                    color: .brandPrimary
                )

                resultCard(
                    icon: "doc.on.doc",
                    title: "重复照片",
                    count: results.duplicates,
                    color: .labelPurple
                )

                resultCard(
                    icon: "externaldrive",
                    title: "大文件",
                    count: results.largeFiles,
                    color: .brandWarning
                )
            }

            Button(action: {
                HapticService.shared.success()
                onboardingManager.nextStep()
            }) {
                HStack(spacing: 8) {
                    Text("开始整理")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(LinearGradient.brand)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .floatingShadow(colorScheme: colorScheme)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 1)
                )
        )
        .glassShadow(colorScheme: colorScheme)
        .padding(.horizontal)
    }

    private func resultCard(icon: String, title: String, count: Int, subtitle: String = "张", color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)

            Text("\(count)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Methods

    private func startAnalysis() {
        Task {
            await onboardingManager.performAnalysis()
        }
    }

    private func updateAnalyzingText(for progress: Double) {
        let index = min(Int(progress * Double(analyzingTexts.count)), analyzingTexts.count - 1)
        withAnimation {
            currentAnalyzingText = analyzingTexts[index]
        }
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    AnalysisLoadingView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    AnalysisLoadingView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
