//
//  ProcessedPhotoManager.swift
//  PhotoSort
//
//  已处理照片管理器 - 记录已分类/整理过的照片ID
//

import Foundation

/// 管理已处理照片的ID，用于筛选不再显示已整理过的照片
class ProcessedPhotoManager {
    // MARK: - Singleton
    
    static let shared = ProcessedPhotoManager()
    
    // MARK: - Properties
    
    private let userDefaults = UserDefaults.standard
    private let processedPhotoIDsKey = "processed_photo_ids"
    
    /// 已处理照片的ID集合
    private var processedIDs: Set<String> {
        get {
            let array = userDefaults.stringArray(forKey: processedPhotoIDsKey) ?? []
            return Set(array)
        }
        set {
            userDefaults.set(Array(newValue), forKey: processedPhotoIDsKey)
        }
    }
    
    /// 已处理照片数量
    var processedCount: Int {
        processedIDs.count
    }
    
    // MARK: - Public Methods
    
    /// 检查照片是否已处理
    /// - Parameter id: 照片的 localIdentifier
    /// - Returns: 是否已处理
    func isProcessed(_ id: String) -> Bool {
        processedIDs.contains(id)
    }
    
    /// 标记照片为已处理
    /// - Parameter id: 照片的 localIdentifier
    func markAsProcessed(_ id: String) {
        var ids = processedIDs
        ids.insert(id)
        processedIDs = ids
    }
    
    /// 批量标记照片为已处理
    /// - Parameter ids: 照片ID数组
    func markAsProcessed(ids: [String]) {
        var currentIDs = processedIDs
        ids.forEach { currentIDs.insert($0) }
        processedIDs = currentIDs
    }
    
    /// 重置所有已处理记录
    func resetAllProcessed() {
        processedIDs = []
    }
    
    /// 获取所有已处理的ID列表
    /// - Returns: ID数组
    func getAllProcessedIDs() -> [String] {
        Array(processedIDs)
    }
    
    /// 从已处理列表中移除特定ID（用于撤销操作）
    /// - Parameter id: 照片ID
    func removeFromProcessed(_ id: String) {
        var ids = processedIDs
        ids.remove(id)
        processedIDs = ids
    }
}
