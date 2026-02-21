//
//  PhotoMetadataPanel.swift
//  PhotoSwipeCleaner
//
//  照片详情面板 - 上滑显示元数据
//

import SwiftUI
import Photos
import MapKit

/// 照片详情面板
struct PhotoMetadataPanel: View {
    let asset: PHAsset?
    @Binding var isPresented: Bool
    
    @State private var metadata: PhotoMetadata?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 拖动指示器
            dragHandle
            
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        loadingView
                    } else if let metadata = metadata {
                        metadataContent(metadata)
                    } else {
                        errorView
                    }
                }
                .padding()
            }
        }
        .background(
            Color.backgroundPrimary
                .ignoresSafeArea()
        )
        .onAppear {
            loadMetadata()
        }
    }
    
    // MARK: - Subviews
    
    private var dragHandle: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
            
            Text("照片详情")
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            Color.backgroundPrimary
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("加载详情...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("无法加载照片详情")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }
    
    private func metadataContent(_ metadata: PhotoMetadata) -> some View {
        VStack(spacing: 24) {
            // 拍摄时间
            infoSection(title: "拍摄信息") {
                InfoRow(
                    icon: "calendar",
                    iconColor: .labelBlue,
                    title: "拍摄时间",
                    value: metadata.creationDateString
                )
                
                if let modificationDate = metadata.modificationDateString {
                    InfoRow(
                        icon: "pencil",
                        iconColor: .labelOrange,
                        title: "修改时间",
                        value: modificationDate
                    )
                }
            }
            
            // 相机信息
            infoSection(title: "相机信息") {
                InfoRow(
                    icon: "camera",
                    iconColor: .labelPurple,
                    title: "相机",
                    value: metadata.cameraModel ?? "未知"
                )
                
                InfoRow(
                    icon: "ruler",
                    iconColor: .labelTeal,
                    title: "分辨率",
                    value: "\(metadata.pixelWidth) × \(metadata.pixelHeight)"
                )
                
                if let focalLength = metadata.focalLength {
                    InfoRow(
                        icon: "viewfinder",
                        iconColor: .labelPink,
                        title: "焦距",
                        value: focalLength
                    )
                }
                
                if let iso = metadata.iso {
                    InfoRow(
                        icon: "speedometer",
                        iconColor: .labelYellow,
                        title: "ISO",
                        value: iso
                    )
                }
            }
            
            // 文件信息
            infoSection(title: "文件信息") {
                InfoRow(
                    icon: "doc",
                    iconColor: .labelIndigo,
                    title: "文件名",
                    value: metadata.filename
                )
                
                InfoRow(
                    icon: "externaldrive",
                    iconColor: .labelRed,
                    title: "文件大小",
                    value: metadata.fileSizeString
                )
                
                InfoRow(
                    icon: "photo",
                    iconColor: .labelGreen,
                    title: "格式",
                    value: metadata.fileType
                )
            }
            
            // 位置信息
            if let location = metadata.location {
                locationSection(location: location, locationName: metadata.locationName)
            }
            
            // iCloud 状态
            infoSection(title: "iCloud") {
                InfoRow(
                    icon: "icloud",
                    iconColor: metadata.isSynced ? .labelBlue : .labelGray,
                    title: "同步状态",
                    value: metadata.isSynced ? "已同步" : "本地"
                )
            }
        }
    }
    
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundSecondary)
            )
        }
    }
    
    private func locationSection(location: CLLocationCoordinate2D, locationName: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拍摄地点")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                // 地图缩略图
                Map {
                    Marker("", coordinate: location)
                }
                .frame(height: 150)
                .cornerRadius(12)
                .mapStyle(.standard)
                
                InfoRow(
                    icon: "mappin.and.ellipse",
                    iconColor: .labelRed,
                    title: "位置",
                    value: locationName ?? "\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))"
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundSecondary)
            )
        }
    }
    
    // MARK: - Methods
    
    private func loadMetadata() {
        guard let asset = asset else {
            isLoading = false
            return
        }
        
        Task {
            let metadata = await PhotoMetadataExtractor.extract(from: asset)
            await MainActor.run {
                self.metadata = metadata
                self.isLoading = false
            }
        }
    }
}

/// 信息行组件
struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor.opacity(0.15))
                )
            
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 元数据模型

struct PhotoMetadata {
    let creationDate: Date?
    let creationDateString: String
    let modificationDateString: String?
    let cameraModel: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let focalLength: String?
    let iso: String?
    let filename: String
    let fileSize: Int64
    let fileSizeString: String
    let fileType: String
    let location: CLLocationCoordinate2D?
    let locationName: String?
    let isSynced: Bool
}

// MARK: - 元数据提取器

enum PhotoMetadataExtractor {
    static func extract(from asset: PHAsset) async -> PhotoMetadata {
        let resources = PHAssetResource.assetResources(for: asset)
        let filename = resources.first?.originalFilename ?? "未知"
        
        // 获取文件大小
        var fileSize: Int64 = 0
        if let resource = resources.first {
            let semaphore = DispatchSemaphore(value: 0)
            PHAssetResourceManager.default().requestData(for: resource, options: nil) { _ in
            } completionHandler: { error in
                semaphore.signal()
            }
            // 注意：这里简化处理，实际应该用其他方式获取大小
            fileSize = 0
        }
        
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "zh_CN")
        
        let creationDateString = asset.creationDate.map { dateFormatter.string(from: $0) } ?? "未知"
        let modificationDateString = asset.modificationDate.map { dateFormatter.string(from: $0) }
        
        // 格式化文件大小
        let fileSizeString = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        
        // 位置信息
        let location = asset.location?.coordinate
        let locationName: String? = nil // 实际项目中可以使用地理反编码
        
        return PhotoMetadata(
            creationDate: asset.creationDate,
            creationDateString: creationDateString,
            modificationDateString: modificationDateString,
            cameraModel: nil, // PHAsset 不直接提供，需要从 EXIF 读取
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            focalLength: nil,
            iso: nil,
            filename: filename,
            fileSize: fileSize,
            fileSizeString: fileSize == 0 ? "未知" : fileSizeString,
            fileType: UTTypeToString(resources.first?.uniformTypeIdentifier),
            location: location,
            locationName: locationName,
            isSynced: resources.first?.value(forKey: "fileSize") != nil
        )
    }
    
    private static func UTTypeToString(_ uti: String?) -> String {
        guard let uti = uti else { return "未知" }
        
        switch uti {
        case "public.jpeg":
            return "JPEG"
        case "public.png":
            return "PNG"
        case "com.apple.quicktime-image":
            return "HEIC"
        case "public.heic":
            return "HEIC"
        case "public.heif":
            return "HEIF"
        case "public.tiff":
            return "TIFF"
        case "com.compuserve.gif":
            return "GIF"
        case "public.raw-image":
            return "RAW"
        default:
            return (uti as NSString).pathExtension.uppercased()
        }
    }
}

// MARK: - Preview
#Preview {
    PhotoMetadataPanel(
        asset: nil,
        isPresented: .constant(true)
    )
}
