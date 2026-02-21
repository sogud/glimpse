# PhotoSwipeCleaner v1.1 更新日志

> **版本**: v1.1.0  
> **更新日期**: 2026-02-07  
> **状态**: 已发布

---

## 概述

v1.1 版本专注于用户体验优化，新增完整的新手引导流程、触觉反馈系统、深色模式适配和设置页面。

---

## 新增功能

### 1. 新手引导流程 (Onboarding)

**解决的问题**: 新用户不知道如何使用滑动操作整理照片

**实现内容**:
- 5 步引导流程: 欢迎页 → 手势教程 → 权限申请 → 智能分析 → 开始整理
- 交互式手势教学: 必须实际完成四个方向的滑动手势才能继续
- 智能分析动画: 模拟扫描相册，展示可优化照片统计
- 进度持久化: 使用 UserDefaults 记录引导完成状态

**关键文件**:
- OnboardingManager.swift
- OnboardingView.swift / WelcomeView.swift
- GestureTutorialView.swift
- PermissionRequestView.swift
- AnalysisLoadingView.swift

---

### 2. 触觉反馈系统 (Haptic)

**解决的问题**: 操作缺乏反馈，用户体验不够精致

**实现内容**:
- 场景化反馈: 删除(重)、保留(轻)、归档(中)、跳过(软)
- 通知类型反馈: 成功、警告、错误
- 庆祝效果: 引导完成时的连续震动反馈

**关键文件**:
- HapticService.swift

---

### 3. 深色模式适配

**解决的问题**: 不支持深色模式，夜间使用刺眼

**实现内容**:
- 完整的语义化颜色系统
- 自动适配系统背景色、标签色
- 优化阴影根据模式调整透明度

**关键文件**:
- Colors.swift
- ContentView.swift
- PhotoCardView.swift

---

### 4. 照片详情面板

**解决的问题**: 无法查看照片的详细信息

**实现内容**:
- 元数据展示: 拍摄时间、相机信息、分辨率、文件大小
- 位置信息: 地图缩略图显示拍摄地点
- iCloud 状态: 显示照片同步状态

**关键文件**:
- PhotoMetadataPanel.swift

---

### 5. 设置页面

**解决的问题**: 无法自定义整理偏好和手势操作

**实现内容**:
- 整理偏好: 自动跳过收藏、删除确认、触觉/声音开关
- 手势自定义: 四个滑动方向可配置不同操作
- 外观设置: 浅色/深色/自动主题切换
- 引导重置: 支持重新显示新手引导

**关键文件**:
- SettingsView.swift

---

## 项目结构更新

```
PhotoSwipeCleaner/
├── App/
│   └── PhotoSwipeCleanerApp.swift    # 更新
├── Core/
│   └── Services/
│       ├── OnboardingManager.swift   # 新增
│       └── HapticService.swift       # 新增
├── UI/
│   ├── Views/
│   │   ├── Onboarding/               # 新增目录
│   │   │   ├── OnboardingView.swift
│   │   │   ├── WelcomeView.swift
│   │   │   ├── GestureTutorialView.swift
│   │   │   ├── PermissionRequestView.swift
│   │   │   └── AnalysisLoadingView.swift
│   │   ├── Components/
│   │   │   └── PhotoMetadataPanel.swift
│   │   └── SettingsView.swift
│   └── Styles/
│       └── Colors.swift
└── View/
    ├── ContentView.swift             # 更新
    ├── SwipeView.swift               # 更新
    └── PhotoCardView.swift           # 更新
```

---

## Bug 修复

| 问题 | 原因 | 修复 |
|------|------|------|
| Color default 参数错误 | SwiftUI 无此 API | 改为直接颜色值 |
| isCloudPlaceholder 不存在 | PHAsset 无此属性 | 改用其他方式判断 |
| Map API 错误 | iOS 17 API 变化 | 简化 Map 定义 |
| onChange 弃用警告 | iOS 17 新签名 | 使用 (old, new) 参数 |
| 开始整理无反应 | 多实例问题 | 使用 EnvironmentObject |

---

## 测试清单

- [x] 新手引导流程完整跑通
- [x] 手势教程必须操作才能继续
- [x] 权限申请和设置跳转
- [x] 触觉反馈各场景正常
- [x] 深色/浅色模式切换
- [x] 设置项持久化
- [x] 引导重置功能

---

## 下一步 (v1.2)

- [ ] 智能分类入口（截图/最近添加/按年份）
- [ ] 批量选择模式
- [ ] 按时间筛选
- [ ] 操作音效

---

**开发耗时**: 约 4 小时  
**新增文件**: 10 个  
**修改文件**: 5 个
