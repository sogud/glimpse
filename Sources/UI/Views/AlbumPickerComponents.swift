//
//  AlbumPickerComponents.swift
//  PhotoSort
//
//  相册选择器共享组件
//

import SwiftUI

/// 相册选择器用的玻璃卡片
struct AlbumPickerSectionCard<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            content

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }
}

/// 相册选择器的单行选项
struct AlbumPickerOptionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var trailingText: String? = nil
    var isSelected: Bool = false
    var selectionTint: Color = .brandPrimary
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if let trailingText {
                Text(trailingText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(selectionTint)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }
}

/// 相册选择器中的分隔线
struct AlbumPickerDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }
}

/// 相册列表加载中的状态卡片内容
struct AlbumPickerLoadingState: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.brandPrimary)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
