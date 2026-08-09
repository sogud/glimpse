import Foundation

/// 当前会话的主任务类型。
enum CleanupWorkflow: String, CaseIterable, Codable, Identifiable {
    case delete
    case organize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .delete:
            return "快速删图"
        case .organize:
            return "归档到相册"
        }
    }

    var entryTitle: String {
        switch self {
        case .delete:
            return "先删一批照片"
        case .organize:
            return "收进同一相册"
        }
    }

    var entryDescription: String {
        switch self {
        case .delete:
            return "别再从整个相册盲滑。先选一个清理场景，每次只处理最多 50 张，更容易做决定。"
        case .organize:
            return "整理相册时不要一轮分多个目标。先选来源，再统一归档到一个相册，决策会轻很多。"
        }
    }
}

/// 快速清理入口，定义本次删图会话的候选集。
enum CleanupPreset: String, CaseIterable, Codable, Identifiable {
    case screenshots
    case videos
    case recentThirtyDays
    case advancedAlbum
    case smartGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots:
            return "截图清理"
        case .videos:
            return "视频清理"
        case .recentThirtyDays:
            return "最近 30 天"
        case .advancedAlbum:
            return "高级来源"
        case .smartGroup:
            return "智能分组"
        }
    }

    var shortTitle: String {
        switch self {
        case .screenshots:
            return "截图"
        case .videos:
            return "视频"
        case .recentThirtyDays:
            return "最近 30 天"
        case .advancedAlbum:
            return "高级来源"
        case .smartGroup:
            return "智能"
        }
    }

    func description(for workflow: CleanupWorkflow) -> String {
        switch (workflow, self) {
        case (.delete, .screenshots):
            return "先清截图和保存图。"
        case (.delete, .videos):
            return "先处理占空间的视频。"
        case (.delete, .recentThirtyDays):
            return "从最近内容开始。"
        case (.delete, .advancedAlbum):
            return "按指定相册或全部照片进入手动清理。"
        case (.organize, .screenshots):
            return "把想留的截图收进相册。"
        case (.organize, .videos):
            return "把想留的视频收进相册。"
        case (.organize, .recentThirtyDays):
            return "从最近内容里挑一批归档。"
        case (.organize, .advancedAlbum):
            return "从指定相册或全部照片里做一轮归档。"
        case (.delete, .smartGroup):
            return "只复核智能筛出的候选。"
        case (.organize, .smartGroup):
            return "只归档智能筛出的候选。"
        }
    }

    var iconName: String {
        switch self {
        case .screenshots:
            return "camera.viewfinder"
        case .videos:
            return "video.fill"
        case .recentThirtyDays:
            return "calendar.badge.clock"
        case .advancedAlbum:
            return "slider.horizontal.3"
        case .smartGroup:
            return "sparkles"
        }
    }
}

/// 一次删图会话的统计结果。
struct CleanupSessionSummary {
    let workflow: CleanupWorkflow
    let preset: CleanupPreset
    let sourceAlbumName: String?
    let targetAlbumName: String?
    let initialCount: Int
    let markedDeleteCount: Int
    let keptCount: Int
    let movedCount: Int
    let estimatedDeletedBytes: Int64
    let hasCommittedPendingDeletes: Bool

    var processedCount: Int {
        markedDeleteCount + keptCount + movedCount
    }

    var remainingCount: Int {
        max(initialCount - processedCount, 0)
    }

    var progressText: String {
        "\(processedCount)/\(initialCount)"
    }

    var estimatedDeletedSizeText: String {
        ByteCountFormatter.string(fromByteCount: estimatedDeletedBytes, countStyle: .file)
    }

    var title: String {
        if preset == .smartGroup, let sourceAlbumName, !sourceAlbumName.isEmpty {
            return sourceAlbumName
        }
        if preset == .advancedAlbum, let sourceAlbumName, !sourceAlbumName.isEmpty {
            return sourceAlbumName
        }
        return preset.title
    }

    var topSubtitle: String {
        switch workflow {
        case .delete:
            return "标记后统一删除，只会在最后确认一次。"
        case .organize:
            if let targetAlbumName, !targetAlbumName.isEmpty {
                return "归档到 \(targetAlbumName)"
            }
            return "归档到相册"
        }
    }
}
