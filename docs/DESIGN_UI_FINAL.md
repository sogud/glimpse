# PhotoSwipeCleaner UI 布局设计（最终版）

> 基于更新后的 PRD：仅左右滑动手势 + 显式撤销按钮

---

## 核心设计原则

1. **极简手势**：只保留左滑删除、右滑归档
2. **显式撤销**：底部独立按钮，不用记手势
3. **全屏照片**：最大化照片展示区域
4. **零学习成本**：一眼就知道怎么用

---

## 界面结构

```
┌─────────────────────────────┐
│ ┌───┐                [?][⚙] │
│ │1/5│                       │  ← 顶部：计数 + 帮助/设置
│ └───┘                       │
│                             │
│                             │
│                             │
│         [照片卡片]           │  ← 核心：占 75% 屏幕
│                             │
│                             │
│                             │
│                             │
├─────────────────────────────┤
│  ← 左滑删除    右滑归档 →    │  ← 手势提示（纯文字）
├─────────────────────────────┤
│          [撤销]             │  ← 底部：撤销按钮
└─────────────────────────────┘
```

---

## 1. 顶部导航栏

### 布局
- **左侧**：照片计数器（小标签样式）
- **右侧**：帮助按钮 + 设置按钮
- **高度**：60pt
- **背景**：透明（让照片延伸上来）

### 照片计数器样式
```
┌────┐
│1/50│  ← 圆角胶囊，半透明背景
└────┘
```

```swift
Text("\(currentIndex + 1)/\(totalCount)")
    .font(.system(size: 14, weight: .semibold))
    .foregroundColor(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
        Capsule()
            .fill(Color.black.opacity(0.4))
    )
```

### 右侧按钮
- 帮助：`questionmark.circle`（打开手势提示）
- 设置：`gearshape`（进入设置页）
- 样式：圆形，半透明背景，白色图标

---

## 2. 照片卡片区域

### 尺寸
- **占满**：除顶部和底部外的所有空间
- **边距**：水平 16pt，垂直 12pt
- **圆角**：20pt

### 卡片内部信息
```
┌────────────────────────┐
│ ┌────┐                 │
│ │1/50│                 │  ← 左上角：计数
│ └────┘                 │
│                        │
│                        │
│        [照片]          │
│                        │
│                        │
│                        │
│  [删除]  ←    →  [归档]│  ← 滑动时显示方向标签
└────────────────────────┘
```

### 滑动方向标签
- **左滑时**：左侧出现红色 "删除" 标签
- **右滑时**：右侧出现蓝色 "归档" 标签
- **样式**：圆角矩形，半透明背景，白色文字

```swift
// 左滑标签（卡片左侧）
Text("删除")
    .font(.title3.bold())
    .foregroundColor(.white)
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .background(
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.swipeDelete)
    )
    .rotationEffect(.degrees(-15))
    .opacity(calculateOpacity(from: offset))
```

---

## 3. 底部区域

### 3.1 手势提示栏

**位置**：照片卡片下方，撤销按钮上方
**高度**：44pt
**样式**：纯文字，居中

```
← 左滑删除        右滑归档 →
```

```swift
HStack {
    Label("左滑删除", systemImage: "arrow.left")
        .foregroundColor(.swipeDelete)

    Spacer()

    Label("右滑归档", systemImage: "arrow.right")
        .foregroundColor(.swipeArchive)
}
.font(.subheadline.weight(.medium))
.padding(.horizontal, 40)
```

### 3.2 撤销按钮

**位置**：屏幕底部，安全区上方
**高度**：56pt
**样式**：胶囊按钮，居中

```swift
Button(action: undoLastAction) {
    HStack(spacing: 6) {
        Image(systemName: "arrow.uturn.backward")
        Text("撤销")
    }
    .font(.system(size: 16, weight: .semibold))
    .foregroundColor(.primary)
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .background(
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    )
}
.disabled(!canUndo)
.opacity(canUndo ? 1 : 0.5)
```

**状态变化**：
- 可撤销：正常显示，可点击
- 不可撤销：透明度 0.5，禁用点击

---

## 4. 相册选择器

### 触发
右滑超过阈值后自动弹出

### 样式
底部 Sheet，高度 50%

```
┌─────────────────────────────┐
│ ───────  drag handle        │
│ 移动到相册              [完成]│
├─────────────────────────────┤
│                             │
│  📁 相机胶卷                 │
│  📁 旅行                     │
│  📁 美食                     │
│  📁 截图                     │
│                             │
│  + 新建相册                  │
│                             │
└─────────────────────────────┘
```

### 交互
- 点击相册：移动照片并关闭
- 点击新建：弹出输入框
- 点击完成/外部：取消移动，照片回位

---

## 5. 空状态

### 全部完成

```
┌─────────────────────────────┐
│                             │
│            ✓                │  ← 大勾选（绿色）
│                             │
│        全部完成！            │
│      本次整理 50 张          │
│                             │
│   删除: 20  归档: 25  保留: 5│
│                             │
│     [ 重新加载照片 ]         │
│                             │
└─────────────────────────────┘
```

### 统计展示
- 本次处理总数
- 删除数量（红色）
- 归档数量（蓝色）
- 保留数量（灰色，未做任何操作的照片）

---

## 6. 配色方案

### 功能色
| 用途 | 颜色 | 值 |
|------|------|-----|
| 删除 | 柔和红 | `#FF6B6B` |
| 归档 | 柔和蓝 | `#5B8DEF` |
| 成功 | 柔和绿 | `#4ADE80` |
| 撤销按钮 | 系统色 | `.ultraThinMaterial` |

### 文字色
- 主文字：`.primary`
- 次文字：`.secondary`
- 计数标签：白色

### 背景
- 主背景：`.systemBackground`
- 卡片背景：白色（浅色模式）/ 深灰（深色模式）

---

## 7. 动画规范

### 卡片滑动
```swift
// 拖动中：实时跟随手指
// 释放后达到阈值
.withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
    // 滑出屏幕
}

// 下一张卡片
.withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
    // 从缩小状态放大到正常
    scale = 1.0
}
```

### 撤销按钮
```swift
// 状态变化时
.animation(.easeInOut(duration: 0.2), value: canUndo)
```

### 方向标签
```swift
// 透明度随滑动距离变化
let opacity = min(abs(offset) / threshold, 1.0)
```

---

## 8. 交互细节

### 滑动阈值
- **触发阈值**：80pt
- **最大偏移**：200pt（限制拖动范围）

### 触觉反馈
- 达到阈值时：轻微震动（`UIImpactFeedbackGenerator`）
- 操作完成时：成功反馈
- 撤销时：点击反馈

### 弹性回弹
- 未达阈值时：弹簧动画回到原位
- 参数：`spring(response: 0.5, dampingFraction: 0.7)`

---

## 9. 尺寸规范

| 元素 | 尺寸 |
|------|------|
| 顶部栏高度 | 60pt |
| 照片卡片边距 | 16pt（水平）12pt（垂直）|
| 卡片圆角 | 20pt |
| 底部提示栏高度 | 44pt |
| 撤销按钮高度 | 56pt |
| 底部安全区 | 系统自动 |

---

## 10. 实施优先级

### Phase 1: 核心手势
- [ ] 实现卡片滑动基础逻辑
- [ ] 左滑删除功能
- [ ] 右滑归档功能

### Phase 2: 视觉反馈
- [ ] 滑动方向标签
- [ ] 卡片切换动画
- [ ] 触觉反馈

### Phase 3: 撤销与选择
- [ ] 底部撤销按钮
- [ ] 操作栈管理
- [ ] 相册选择器

### Phase 4: 完善
- [ ] 空状态页面
- [ ] 统计展示
- [ ] 设置页

---

## 11. 与当前代码的对比

| 元素 | 当前 | 新设计 |
|------|------|--------|
| 手势 | 上下左右 | 仅左右 |
| 底部按钮 | 双行5个按钮 | 仅撤销按钮 |
| 操作提示 | 带背景提示栏 | 纯文字 |
| 照片占比 | ~60% | ~75% |
| 撤销 | 按钮在按钮群中 | 独立底部按钮 |

---

## 12. 关键代码结构

```swift
// ContentView 布局
VStack(spacing: 0) {
    // 顶部导航
    HStack {
        photoCounter
        Spacer()
        helpButton
        settingsButton
    }

    // 照片卡片
    SwipeCardView(viewModel: viewModel)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

    // 手势提示
    HStack {
        Label("左滑删除", systemImage: "arrow.left")
        Spacer()
        Label("右滑归档", systemImage: "arrow.right")
    }

    // 撤销按钮
    UndoButton(canUndo: viewModel.canUndo) {
        viewModel.undo()
    }
    .padding(.bottom, 20)
}
```

---

**总结**：这个设计把手势减到最少（只有左右），撤销独立显示，底部简洁，照片区域最大化。用户只需要记住：左滑删，右滑存，错了点撤销。
