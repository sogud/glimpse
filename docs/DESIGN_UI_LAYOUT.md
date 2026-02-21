# PhotoSwipeCleaner UI 布局设计文档

## 当前问题分析

### 1. 视觉层次混乱
- 底部控制按钮区域过高，占用太多屏幕空间
- 滑动提示栏与底部按钮功能重复，造成信息冗余
- 卡片区域被压缩，照片展示空间不足

### 2. 交互元素分布不合理
- 操作按钮分散在两行，用户视线需要上下移动
- 删除/保留作为主要操作，却与次要操作（撤销、跳过、归档）混排
- 缺少明确的视觉焦点

### 3. 信息密度过高
- 滑动提示栏 + 底部双行按钮 = 过于复杂的底部区域
- 用户看到太多选项，决策成本增加

---

## 设计目标

1. **简洁优先**：减少屏幕上的元素数量
2. **操作直观**：核心操作一目了然
3. **空间合理**：给照片展示留出足够空间
4. **层次清晰**：视觉权重分配合理

---

## 新布局方案

### 整体结构

```
┌─────────────────────────────┐
│  标题              [?] [⚙]  │  ← 顶部导航栏（精简）
├─────────────────────────────┤
│                             │
│                             │
│        照片卡片区域          │  ← 核心区域（最大化）
│        (占据70%屏幕)         │
│                             │
│                             │
├─────────────────────────────┤
│      ← 滑动提示 →           │  ← 一行简洁提示
├─────────────────────────────┤
│    [删除]  [跳过]  [归档]   │  ← 底部操作栏（三个按钮）
│      ↓ 左滑保留 ↓           │  ← 保留操作改为左滑手势
└─────────────────────────────┘
```

---

## 详细设计规范

### 1. 顶部导航栏

**位置**：固定顶部
**高度**：60pt
**内容**：
- 左侧：应用标题 "PhotoSwipeCleaner"（或简化为 "照片整理"）
- 右侧：帮助按钮 + 设置按钮（保持当前样式）
- 移除：照片计数器（移至卡片内部）

**样式**：
```swift
// 标题样式
.font(.system(size: 20, weight: .semibold))
.foregroundColor(.primary)

// 按钮样式（保持玻璃拟态）
.frame(width: 40, height: 40)
.background(Circle().fill(.ultraThinMaterial))
```

---

### 2. 照片卡片区域

**位置**：屏幕中央
**占比**：垂直方向 65-70%
**边距**：水平 20pt

**卡片内部新增**：
- 左上角：照片计数 "1/50"
- 右上角：日期信息（如果空间允许）

**卡片样式**：
```swift
// 圆角
.cornerRadius(20)

// 阴影（更柔和）
.shadow(color: Color.black.opacity(0.1), radius: 16, x: 0, y: 6)

// 边框（可选）
.overlay(
    RoundedRectangle(cornerRadius: 20)
        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
)
```

---

### 3. 滑动提示栏（精简版）

**位置**：卡片下方，底部按钮上方
**高度**：40pt
**样式**：纯文字提示，无背景

**内容**：
```
← 删除    ↑ 归档    ↓ 跳过    → 保留
```

**实现**：
```swift
HStack(spacing: 24) {
    Label("删除", systemImage: "arrow.left")
        .foregroundColor(.swipeDelete)
    Label("归档", systemImage: "arrow.up")
        .foregroundColor(.swipeArchive)
    Label("跳过", systemImage: "arrow.down")
        .foregroundColor(.swipeSkip)
    Label("保留", systemImage: "arrow.right")
        .foregroundColor(.swipeKeep)
}
.font(.system(size: 12, weight: .medium))
```

**设计理由**：
- 去掉背景，减少视觉重量
- 纯文字+图标，信息传达直接
- 小字号，不抢主体照片的风头

---

### 4. 底部操作栏（重新设计）

**位置**：屏幕底部
**高度**：80pt（包含安全区域）
**布局**：三个主要按钮横向排列

#### 按钮设计

| 位置 | 操作 | 图标 | 颜色 | 说明 |
|------|------|------|------|------|
| 左侧 | 删除 | trash.fill | swipeDelete (红) | 点击删除当前照片 |
| 中央 | 跳过 | arrow.down.circle.fill | swipeSkip (灰) | 点击跳过当前照片 |
| 右侧 | 归档 | folder.badge.plus | swipeArchive (蓝) | 点击打开相册选择器 |

#### 保留操作的处理

**方案A（推荐）**：右滑手势保留
- 删除用户的"保留"按钮
- 通过右滑手势保留照片
- 在滑动提示栏中明确标注 "→ 保留"

**方案B**：长按保留
- 长按卡片任意位置保留
- 显示 "长按保留" 提示

#### 按钮样式规范

```swift
// 按钮容器
VStack(spacing: 4) {
    Image(systemName: icon)
        .font(.system(size: 24))
    Text(label)
        .font(.system(size: 11, weight: .medium))
}
.foregroundColor(color)
.frame(width: 64, height: 64)
.background(
    Circle()
        .fill(color.opacity(0.12))
)

// 底部栏背景
.background(
    .ultraThinMaterial
)
```

---

### 5. 撤销操作的处理

**问题**：撤销是低频操作，不应占用底部主要位置

**解决方案**：

方案A（推荐）：SnackBar 样式
```
┌─────────────────────────────┐
│  已删除 1 张照片      [撤销] │  ← 显示3秒后自动消失
└─────────────────────────────┘
```

方案B：顶部工具栏
- 在顶部导航栏右侧添加小型撤销按钮
- 只有可撤销时才显示

---

## 交互细节

### 手势优先级
1. **水平滑动**：删除（左）/ 保留（右）
2. **垂直滑动**：归档（上）/ 跳过（下）
3. **点击按钮**：与手势等效的操作

### 视觉反馈
- 滑动时卡片跟随手指移动
- 达到阈值时显示方向标签（删除/保留等）
- 按钮点击时有缩放动画（scale 0.9）

### 空状态
当所有照片处理完毕时：
- 显示大勾选图标
- 文字："全部完成！"
- 按钮："重新加载"

---

## 深色模式适配

所有颜色使用 Semantic Colors 或自定义适配：

```swift
// 背景
.backgroundPrimary: Color(.systemBackground)

// 文字
.primary / .secondary

// 操作色（保持一致）
.swipeDelete: Color(red: 1, green: 0.42, blue: 0.42)
.swipeKeep: Color(red: 0.298, green: 0.851, blue: 0.392)
.swipeArchive: Color(red: 0.357, green: 0.557, blue: 0.937)
.swipeSkip: Color(red: 0.6, green: 0.6, blue: 0.65)
```

---

## 实施优先级

### Phase 1: 精简底部栏
- [ ] 移除底部双行按钮
- [ ] 实现三按钮布局（删除、跳过、归档）
- [ ] 将保留操作改为右滑手势

### Phase 2: 优化提示栏
- [ ] 移除带背景的滑动提示栏
- [ ] 实现精简文字提示
- [ ] 将照片计数移至卡片内部

### Phase 3: 撤销功能重构
- [ ] 实现 SnackBar 样式撤销提示
- [ ] 从底部栏移除撤销按钮

### Phase 4: 细节优化
- [ ] 调整卡片阴影和圆角
- [ ] 优化动画效果
- [ ] 测试不同屏幕尺寸

---

## 参考设计

### 优秀案例
1. **Tinder**：简洁的卡片堆叠，底部只有几个操作按钮
2. **Google Photos**：简洁的底部工具栏
3. **iOS 照片 app**：原生设计风格

### 避免的坑
1. 不要同时提供按钮和手势做同一件事（信息冗余）
2. 不要让底部栏超过屏幕高度的 20%
3. 不要使用过多颜色（保持 3-4 种主色）

---

## 技术实现备注

### 需要修改的文件
- `ContentView.swift` - 重新设计底部栏和顶部导航
- `SwipeView.swift` - 优化滑动提示，移除冗余元素
- `PhotoCardView.swift` - 添加照片计数显示

### 新增组件
- `UndoToast` - SnackBar 样式撤销提示

### 删除的代码
- 双行底部按钮布局
- 带背景的滑动提示栏
- 独立的保留按钮（改为手势）
