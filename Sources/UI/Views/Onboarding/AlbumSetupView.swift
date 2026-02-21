//
//  AlbumSetupView.swift
//  PhotoSwipeCleaner
//
//  首次使用相册设置引导页
//

import SwiftUI
import Photos

/// 首次使用的相册设置引导页
struct AlbumSetupView: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            ZStack {
                // 背景
                LinearGradient.background
                    .ignoresSafeArea()

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
            }
            .navigationTitle("设置相册")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("跳过") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .onAppear {
                loadAlbums()
                // 初始化输入框
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
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.brandPrimary)
            }
            .padding(.top, 20)

            Text("设置目标相册")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }

    private var descriptionView: some View {
        VStack(spacing: 8) {
            Text("选择左右滑动对应的目标相册")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("整理时照片将被移动到对应相册，无需确认弹窗")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var albumSelectionArea: some View {
        VStack(spacing: 20) {
            // 左滑相册选择
            albumSelectionCard(
                icon: "arrow.left",
                iconColor: .swipeDelete,
                title: "左滑相册",
                subtitle: "不想保留的照片",
                albumName: $leftAlbumInput,
                showingPicker: $showingLeftAlbumPicker
            )

            // 右滑相册选择
            albumSelectionCard(
                icon: "arrow.right",
                iconColor: .swipeKeep,
                title: "右滑相册",
                subtitle: "想要保留的照片",
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
        subtitle: String,
        albumName: Binding<String>,
        showingPicker: Binding<Bool>
    ) -> some View {
        Button(action: { showingPicker.wrappedValue = true }) {
            HStack(spacing: 16) {
                // 图标
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(iconColor.opacity(0.12))
                    )

                // 文字
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(albumName.wrappedValue.isEmpty ? subtitle : albumName.wrappedValue)
                        .font(.subheadline)
                        .foregroundColor(albumName.wrappedValue.isEmpty ? .secondary : iconColor)
                }

                Spacer()

                // 箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(iconColor.opacity(albumName.wrappedValue.isEmpty ? 0.1 : 0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var bottomButtons: some View {
        VStack(spacing: 16) {
            // 完成按钮
            Button(action: saveAndDismiss) {
                HStack(spacing: 8) {
                    Text(canSave ? "完成设置" : "请设置至少一个相册")
                        .font(.headline)
                        .fontWeight(.semibold)

                    if canSave {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    canSave ? LinearGradient.brand : LinearGradient(colors: [.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .floatingShadow(colorScheme: colorScheme)
            }
            .disabled(!canSave)
            .opacity(canSave ? 1.0 : 0.6)

            // 提示
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("之后可以在设置中随时修改")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !leftAlbumInput.isEmpty || !rightAlbumInput.isEmpty
    }

    private func loadAlbums() {
        isLoading = true

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
        isLoading = false
    }

    private func saveAndDismiss() {
        swipeLeftAlbum = leftAlbumInput
        swipeRightAlbum = rightAlbumInput
        HapticService.shared.success()
        dismiss()
    }
}

// MARK: - Album Picker Sheet

struct AlbumPickerSheet: View {
    @Binding var selectedAlbum: String
    let albums: [PHAssetCollection]
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var newAlbumName = ""
    @State private var showingCreateAlert = false

    var body: some View {
        NavigationView {
            List {
                // 创建新相册
                Button(action: { showingCreateAlert = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.brandPrimary)
                        Text("创建新相册")
                            .foregroundColor(.primary)
                    }
                }

                // 现有相册
                Section(header: Text("选择已有相册")) {
                    ForEach(albums, id: \.localIdentifier) { album in
                        Button(action: {
                            selectedAlbum = album.localizedTitle ?? "未知相册"
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.brandPrimary)
                                Text(album.localizedTitle ?? "未知相册")
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedAlbum == album.localizedTitle {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("创建新相册", isPresented: $showingCreateAlert) {
                TextField("相册名称", text: $newAlbumName)
                Button("取消", role: .cancel) {
                    newAlbumName = ""
                }
                Button("创建") {
                    if !newAlbumName.isEmpty {
                        selectedAlbum = newAlbumName
                        dismiss()
                    }
                }
            } message: {
                Text("请输入新相册的名称")
            }
        }
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    AlbumSetupView()
}

#Preview("Dark Mode") {
    AlbumSetupView()
        .preferredColorScheme(.dark)
}
