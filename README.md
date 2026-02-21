# PhotoSwipeCleaner

一款简洁高效的 iOS 照片整理应用，通过左右滑动快速整理相册。

## 功能特性

- **滑动整理**：左右滑动照片，快速决定保留或删除
- **视频支持**：支持视频预览和播放
- **相册管理**：将照片移动到指定相册
- **撤销功能**：所有操作都可撤销
- **批量处理**：支持按相册筛选整理
- **手势动画**：流畅的卡片滑动动画
- **暗黑模式**：支持浅色/深色主题

## 技术栈

- SwiftUI
- iOS 18.2+
- PhotoKit
- AVKit

## 安装

1. 克隆项目
```bash
git clone https://github.com/yourusername/PhotoSwipeCleaner.git
```

2. 打开项目
```bash
cd PhotoSwipeCleaner
open PhotoSort.xcodeproj
```

3. 构建并运行（需要 Xcode 16.2+）

## 使用说明

1. 首次启动授予相册权限
2. 设置左滑/右滑目标相册
3. 开始滑动整理照片
4. 使用底部撤销按钮回退操作

## 项目结构

```
PhotoSort/
├── App/                    # 应用入口
├── Model/                  # 数据模型
├── View/                   # UI 视图
├── ViewModel/              # 视图模型
├── Service/                # 服务层
├── Core/Services/          # 核心服务
└── UI/                     # UI 组件
```

## 截图

（待添加）

## License

MIT License

## 作者

Your Name
