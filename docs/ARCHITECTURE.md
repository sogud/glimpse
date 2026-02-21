# PhotoSwipeCleaner 架构设计文档

## 项目概述

PhotoSwipeCleaner 是一款 iOS 照片整理应用，采用 Tinder 风格的卡片滑动界面，让用户通过简单手势快速分类照片。

**核心功能：**
- 左右滑动将照片移动到不同相册
- 支持硬删除模式
- 撤销操作支持
- 新手引导流程
- 深色/浅色模式适配

---

## 架构模式

### MVVM 架构

采用 **Model-View-ViewModel** 架构模式，确保关注点分离和可测试性：

```
┌─────────────────────────────────────────────────────────────┐
│                         View Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ ContentView  │  │  SwipeView   │  │PhotoCardView │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      ViewModel Layer                        │
│              ┌───────────────────────┐                      │
│              │ PhotoSwipeViewModel   │                      │
│              │      (@MainActor)     │                      │
│              └───────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Service/Model Layer                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │PhotoLibrary  │  │ PhotoAsset   │  │  Onboarding  │       │
│  │  Service     │  │   (Model)    │  │   Manager    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    External Framework                       │
│                       (PhotoKit)                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 目录结构

```
PhotoSwipeCleaner/
├── App/                              # 应用入口
│   └── PhotoSwipeCleanerApp.swift    # @main 应用入口，RootView 路由
│
├── Model/                            # 数据模型层
│   └── PhotoAsset.swift              # PHAsset 包装类，图片加载管理
│
├── View/                             # 核心视图层
│   ├── ContentView.swift             # 主容器，权限处理，控制栏
│   ├── SwipeView.swift               # 滑动交互容器，卡片堆叠
│   ├── PhotoCardView.swift           # 单个照片卡片 UI
│   └── AlbumPickerView.swift         # 相册选择 Sheet
│
├── ViewModel/                        # 视图模型层
│   └── PhotoSwipeViewModel.swift     # 业务逻辑协调器 (@MainActor)
│
├── Service/                          # 服务层
│   └── PhotoLibraryService.swift     # PhotoKit 封装，相册操作
│
├── Core/                             # 核心服务
│   └── Services/
│       ├── OnboardingManager.swift   # 引导流程状态管理
│       └── HapticService.swift       # 触觉反馈封装
│
├── UI/                               # UI 组件和样式
│   ├── Styles/
│   │   ├── Colors.swift              # 颜色系统，玻璃拟态
│   │   └── Animations.swift          # 动画定义
│   └── Views/
│       ├── Components/               # 可复用组件
│       ├── Onboarding/               # 引导页面
│       └── SettingsView.swift        # 设置页面
│
└── Utils/                            # 工具类
    └── GestureDirection.swift        # 滑动手势方向枚举
```

---

## 核心模块详解

### 1. Model 层

#### PhotoAsset

`PHAsset` 的 SwiftUI 包装类，处理图片异步加载：

```swift
class PhotoAsset: ObservableObject {
    let asset: PHAsset
    @Published var image: UIImage?
    @Published var isLoading: Bool

    func loadImage(targetSize: CGSize, contentMode: PHImageContentMode)
}
```

**设计要点：**
- 使用 `PHImageManager` 异步加载图片
- 支持自定义 targetSize 和 contentMode
- 使用 `@Published` 触发 UI 更新

---

### 2. ViewModel 层

#### PhotoSwipeViewModel

主业务逻辑协调器，使用 `@MainActor` 确保线程安全：

**核心职责：**
- 管理照片列表 (`allPhotos`)
- 跟踪当前位置 (`currentIndex`)
- 处理滑动操作 (delete/move/keep)
- 维护撤销栈 (`undoStack`)

**关键方法：**
```swift
func loadPhotos() async throws          // 加载照片（支持相册过滤）
func handleSwipe(_ direction: GestureDirection)  // 处理滑动
func deletePhoto(_ asset: PHAsset)      // 删除照片
func movePhotoToAlbum(_ asset: PHAsset, albumName: String)  // 移动到相册
func undoLastAction()                   // 撤销操作
```

**撤销机制：**
```swift
private var undoStack: [(action: String, asset: PHAsset, index: Int)]
```

---

### 3. Service 层

#### PhotoLibraryService

封装所有 PhotoKit 交互，提供类型安全接口：

```swift
class PhotoLibraryService {
    func fetchPhotos(limit: Int, excludeAlbums: [String]) throws -> [PHAsset]
    func deletePhoto(_ asset: PHAsset) async throws -> Bool
    func movePhotoToAlbum(_ asset: PHAsset, albumName: String) async throws -> Bool
}
```

**特性：**
- 支持 iOS 14+ 的 Limited 权限模式
- 相册不存在时自动创建
- 智能过滤已分类照片

---

### 4. View 层

#### SwipeView

滑动交互的核心容器：

**卡片堆叠效果：**
- 当前卡片：scale=1.0, opacity=1.0
- 第二张：scale=0.98, opacity=0.7, offsetY=6
- 第三张：scale=0.96, opacity=0.4, offsetY=12

**手势处理：**
- 水平滑动阈值：80pt
- 最大偏移限制：200pt
- 支持按钮触发滑动（通过 NotificationCenter）

#### PhotoCardView

拍立得风格卡片：
- 白色边框背景
- 日期标签在底部
- 滑动方向遮罩层
- 根据偏移量动态旋转（rotation = offset.width / 25）

#### ContentView

主容器布局：
```
┌──────────────────────────────┐
│  顶部信息栏 (计数器/设置)        │
├──────────────────────────────┤
│                              │
│       照片滑动区域             │
│       (SwipeView)            │
│                              │
├──────────────────────────────┤
│  底部控制栏 (左/撤销/右)       │
└──────────────────────────────┘
```

---

## 数据流

### 照片加载流程

```
1. ContentView.onAppear
         │
         ▼
2. PhotoSwipeViewModel.loadPhotos()
         │
         ├─ 读取 UserDefaults 获取目标相册
         │
         ▼
3. PhotoLibraryService.fetchPhotos(excludeAlbums:)
         │
         ├─ 查询排除相册中的所有 asset ID
         ├─ 获取所有照片
         └─ 过滤已分类照片
         │
         ▼
4. 创建 PhotoAsset 数组
         │
         ▼
5. currentPhoto.loadImage()
         │
         ▼
6. PHImageManager.requestImage
         │
         ▼
7. 图片加载完成 → UI 更新
```

### 滑动操作流程

```
用户滑动/点击按钮
        │
        ▼
SwipeView.performAction(.left/.right)
        │
        ├─ 播放触觉反馈
        ├─ 动画滑出卡片
        │
        ▼
ViewModel.handleSwipe() / moveToAlbum()
        │
        ▼
PhotoLibraryService (delete/move)
        │
        ▼
PhotoKit 操作
        │
        ▼
更新本地数组 (removeCurrentPhoto)
        │
        ▼
撤销栈记录操作
```

---

## 关键设计决策

### 1. 线程安全

- `PhotoSwipeViewModel` 使用 `@MainActor`
- UI 更新必须在主线程执行
- PhotoKit 回调通过 `DispatchQueue.main.async` 处理

### 2. 状态管理

- 使用 `@Published` 实现响应式 UI
- `UserDefaults` 存储用户设置（相册配置、权限状态）
- `@AppStorage` 在 SwiftUI 中直接绑定设置

### 3. 图片加载优化

```swift
// 使用较大的 targetSize 保持清晰度
loadImage(targetSize: CGSize(width: 1200, height: 1200))

// aspectFit 保持原图比例
contentMode: .aspectFit

// fast 模式避免强制缩放
options.resizeMode = .fast
```

### 4. 手势设计

| 方向 | 操作 | 颜色 |
|------|------|------|
| 左滑 | 删除/移动到左滑相册 | 红色 |
| 右滑 | 移动到右滑相册 | 绿色 |
| 上滑 | 归档（保留原图） | 蓝色 |
| 下滑 | 跳过 | 灰色 |

---

## 扩展性设计

### 添加新的滑动操作

1. 在 `GestureDirection` 中定义方向
2. 在 `SwipeView.performAction` 中处理
3. 在 `PhotoCardView.swipeOverlay` 中添加 UI

### 添加新的设置选项

1. 在 `UserDefaults` 中添加 key
2. 在 `SettingsView` 中添加 UI
3. 在 `ContentView` 中使用 `@AppStorage` 读取

---

## 已知问题与改进建议

### 代码审查发现

| 优先级 | 问题 | 建议 |
|--------|------|------|
| HIGH | Task 闭包强引用 self | 添加 `[weak self]` |
| MEDIUM | PhotoAsset 未取消图片请求 | 存储 requestID 在 deinit 取消 |
| MEDIUM | 未使用的 cancellables | 移除 Combine 相关代码 |
| SUGGESTION | DateFormatter 重复创建 | 使用静态缓存 |

### 功能改进建议

1. **批量操作**：支持多选批量移动/删除
2. **智能分类**：基于 AI 的重复照片检测
3. **云同步**：iCloud 支持跨设备同步
4. **Widget**：主屏幕小组件显示整理进度

---

## 技术栈

- **语言**：Swift 5.0+
- **框架**：SwiftUI, PhotoKit, UIKit (部分)
- **最低版本**：iOS 18.2+
- **开发环境**：Xcode 16.2+

---

## 参考资料

- `AGENTS.md`：开发指南和常见任务
- `PRODUCT_DOC.md`：产品需求文档
- `CLAUDE.md`：项目基本说明
