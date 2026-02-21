//
//  OnboardingAlbumSetupView.swift
//  PhotoSwipeCleaner
//
//  引导流程中的相册设置页面
//

import SwiftUI
import Photos

/// 引导流程中的相册设置页面
struct OnboardingAlbumSetupView: View {
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme

    // 用户设置
    @AppStorage("swipeLeftAlbum") private var swipeLeftAlbum: String = ""
    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""

    // 本地状态
    @State private var leftAlbumInput = ""
    @State private var rightAlbumInput = ""
    @State private var showingLeftAlbumPicker = false
    @State private var showingRightAlbumPicker = false
    @State private var albums: [PHAssetCollection] = []

    var body: some View {
        VStack(spacing: 24) {
            // 标题区域
            headerView

            // 说明文字
            descriptionView

            // 相册选择区域
            albumSelectionArea

            Spacer()

            // 底部按钮
            bottomButtons
        }
        .padding()
        .onAppear {
            loadAlbums()
            leftAlbumInput = swipeLeftAlbum
            rightAlbumInput = swipeRightAlbum
        }
        .sheet(isPresented: $showingLeftAlbumPicker) {
            AlbumPickerSheet(
                selectedAlbum: $leftAlbumInput,
                albums: albums,
                title: "选择左滑相册"
            )
        }
        .sheet(isPresented: $showingRightAlbumPicker) {
            AlbumPickerSheet(
                selectedAlbum: $rightAlbumInput,
                albums: albums,
                title: "选择右滑相册"
            )
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: 12) {
            Text("设置目标相册")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("选择相册，整理更流畅")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    private var descriptionView: some View {
        VStack(spacing: 8) {
            Text("左右滑动将把照片移动到对应相册")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("无需每次确认，整理效率更高")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var albumSelectionArea: some View {
        VStack(spacing: 16) {
            // 左滑相册选择
            albumSelectionCard(
                icon: "arrow.left",
                iconColor: .swipeDelete,
                title: "左滑相册",
                description: "不想保留的照片",
                albumName: $leftAlbumInput,
                showingPicker: $showingLeftAlbumPicker
            )

            // 右滑相册选择
            albumSelectionCard(
                icon: "arrow.right",
                iconColor: .swipeKeep,
                title: "右滑相册",
                description: "想要保留的照片",
                albumName: $rightAlbumInput,
                showingPicker: $showingRightAlbumPicker
            )
        }
        .padding(.horizontal)
    }

    private func albumSelectionCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        albumName: Binding<String>,
        showingPicker: Binding<Bool>
    ) -> some View {
        Button(action: { showingPicker.wrappedValue = true }) {
            HStack(spacing: 16) {
                // 图标
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(iconColor.opacity(0.12))
                    )

                // 文字
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(albumName.wrappedValue.isEmpty ? "点击选择相册" : albumName.wrappedValue)
                        .font(.caption)
                        .foregroundColor(albumName.wrappedValue.isEmpty ? .secondary : iconColor)
                }

                Spacer()

                // 状态指示
                if albumName.wrappedValue.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.swipeKeep)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(iconColor.opacity(albumName.wrappedValue.isEmpty ? 0.1 : 0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var bottomButtons: some View {
        VStack(spacing: 16) {
            // 继续按钮
            Button(action: saveAndContinue) {
                HStack(spacing: 8) {
                    Text(canContinue ? "继续" : "请至少设置一个相册")
                        .font(.headline)
                        .fontWeight(.semibold)

                    if canContinue {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    canContinue ? LinearGradient.brand : LinearGradient(colors: [.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .floatingShadow(colorScheme: colorScheme)
            }
            .disabled(!canContinue)
            .opacity(canContinue ? 1.0 : 0.6)

            // 页码指示器
            PageIndicator(currentPage: 3, totalPages: OnboardingStep.allCases.count)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    private var canContinue: Bool {
        !leftAlbumInput.isEmpty || !rightAlbumInput.isEmpty
    }

    private func loadAlbums() {
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        var loadedAlbums: [PHAssetCollection] = []
        userAlbums.enumerateObjects { collection, _, _ in
            if collection.localizedTitle != nil {
                loadedAlbums.append(collection)
            }
        }

        albums = loadedAlbums
    }

    private func saveAndContinue() {
        swipeLeftAlbum = leftAlbumInput
        swipeRightAlbum = rightAlbumInput
        HapticService.shared.success()
        onboardingManager.nextStep()
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    OnboardingAlbumSetupView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    OnboardingAlbumSetupView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
