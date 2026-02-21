# PhotoSwipeCleaner 打包部署手册

## 目录
1. [开发调试安装（免费）](#方式一开发调试安装免费)
2. [TestFlight 分发测试](#方式二testflight-分发测试)
3. [App Store 上架](#方式三app-store-上架)
4. [常见问题排查](#常见问题排查)

---

## 方式一：开发调试安装（免费）

适用于：开发者自己使用，或临时给朋友安装测试

### 前置要求
- macOS 系统
- Xcode 16.2+ 已安装
- Apple ID（免费账号即可）
- iPhone（iOS 18.2+）
- USB 数据线

### 步骤 1：连接设备
1. 用 USB 线将 iPhone 连接到 Mac
2. 解锁 iPhone，点击"信任此电脑"

### 步骤 2：配置 Xcode
1. 打开 Xcode
2. 打开项目：`File → Open → 选择 PhotoSwipeCleaner.xcodeproj`
3. 等待项目索引完成

### 步骤 3：选择签名账号
1. 点击左侧项目导航栏最顶部的 `PhotoSwipeCleaner`
2. 选择 `Signing & Capabilities` 标签
3. 在 `Team` 下拉框中选择你的 Apple ID
   - 如果没有，点击 `Add Account...` 登录 Apple ID

### 步骤 4：选择目标设备
1. 点击顶部工具栏的运行目标（默认显示模拟器名称）
2. 在列表中选择你的 iPhone（显示为 `Your Name's iPhone`）

### 步骤 5：修改 Bundle Identifier（首次需要）
1. 在 `Signing & Capabilities` 页面
2. 修改 `Bundle Identifier` 为唯一值，例如：
   ```
   com.yourname.photoswipecleaner
   ```
   或者添加随机数字：
   ```
   com.changshun.PhotoSwipeCleaner123
   ```

### 步骤 6：运行安装
1. 点击运行按钮（▶）或按 `Cmd+R`
2. 等待编译完成
3. 首次安装会在 iPhone 上提示"不信任的开发者"

### 步骤 7：信任开发者证书
1. 在 iPhone 上打开 `设置`
2. 进入 `通用 → VPN与设备管理`（或`描述文件与设备管理`）
3. 找到你的 Apple ID，点击 `信任`
4. 再次确认信任

### 步骤 8：启动应用
1. 返回主屏幕
2. 点击 `PhotoSwipeCleaner` 图标
3. 授予相册权限，开始使用

### 免费账号限制
- **7天有效期**：应用每7天需要重新连接电脑安装
- **3台设备限制**：最多同时安装到3台设备
- **无法上架**：不能发布到 App Store

---

## 方式二：TestFlight 分发测试

适用于：给多位朋友测试，或长期测试（90天有效期）

### 前置要求
- Apple Developer Program 账号（$99/年）
- 已完成 App 开发

### 步骤 1：注册开发者账号
1. 访问 [developer.apple.com](https://developer.apple.com)
2. 使用 Apple ID 登录
3. 加入 Apple Developer Program
4. 完成付款（$99/年）
5. 等待账号激活（通常即时生效）

### 步骤 2：配置 App ID
1. 访问 [App Store Connect](https://appstoreconnect.apple.com)
2. 登录开发者账号
3. 进入 `Identifiers` 页面
4. 点击 `+` 创建新的 App ID
   - 选择 `App IDs`
   - Description: `PhotoSwipeCleaner`
   - Bundle ID: `Explicit`，输入与项目相同的 Bundle ID
   - Capabilities: 勾选 `Photos` 权限
5. 点击 `Continue` → `Register`

### 步骤 3：创建应用记录
1. 在 App Store Connect 中进入 `Apps`
2. 点击 `+` → `New App`
3. 填写信息：
   - Platforms: `iOS`
   - Name: `PhotoSwipeCleaner`（如果已被占用，加后缀如 `PhotoSwipeCleaner Beta`）
   - Primary Language: `Chinese (Simplified)`
   - Bundle ID: 选择刚才创建的
   - SKU: `photoswipecleaner001`（任意唯一值）
   - User Access: `Full Access`
4. 点击 `Create`

### 步骤 4：归档构建
1. 在 Xcode 中选择 `Any iOS Device (arm64)` 作为目标
2. 菜单栏选择 `Product → Archive`
3. 等待编译归档完成
4. 归档管理器自动打开（或选择 `Window → Organizer`）

### 步骤 5：上传构建版本
1. 在 Organizer 中选择最新的 Archive
2. 点击 `Distribute App`
3. 选择 `App Store Connect`
4. 选择 `Upload`
5. 保持默认选项，点击 `Next`
6. 等待上传完成（可能需要10-30分钟）

### 步骤 6：配置 TestFlight
1. 在 App Store Connect 中进入你的应用
2. 选择 `TestFlight` 标签
3. 在 `Internal Testing` 中添加测试人员
   - 输入测试人员的 Apple ID 邮箱
   - 测试人员会收到邮件邀请
4. 或者使用 `External Testing`：
   - 点击 `+` 创建新的测试组
   - 设置测试信息
   - 提交审核（通常几小时内通过）

### 步骤 7：测试人员安装
1. 测试人员在 iPhone 上安装 `TestFlight` App（App Store 下载）
2. 打开 TestFlight，接受邀请
3. 点击 `Install` 安装 PhotoSwipeCleaner
4. 应用有效期 90 天

---

## 方式三：App Store 上架

适用于：正式发布给所有用户

### 前置要求
- 完成应用开发和测试
- 准备应用截图（iPhone 各种尺寸）
- 准备应用描述、关键词、隐私政策链接

### 步骤 1：准备上架材料
| 材料 | 要求 |
|------|------|
| 应用截图 | iPhone 6.7"、6.5"、5.5" 截图各3-5张 |
| 应用图标 | 1024×1024 PNG |
| 应用描述 | 简短介绍应用功能 |
| 关键词 | 帮助用户搜索到应用 |
| 隐私政策 | 网页链接，说明数据使用 |

### 步骤 2：填写应用信息
1. 在 App Store Connect → 应用 → `App Store` 标签
2. 填写所有必填项：
   - 应用名称、副标题
   类别：`摄影与录像`
   - 年龄分级：`4+`
   - 价格：`免费`
   - 截图和预览视频

### 步骤 3：提交审核
1. 在 `App Store` 标签页点击 `Submit for Review`
2. 回答出口合规、广告标识符等问题
3. 确认所有信息完整
4. 提交审核

### 步骤 4：等待审核
- 审核时间：通常 1-3 个工作日
- 可能的结果：通过、拒绝（会邮件说明原因）、需要更多信息

### 步骤 5：发布
- 审核通过后，选择自动发布或手动发布
- 应用在 App Store 上架，用户可搜索下载

---

## 常见问题排查

### 问题 1：Xcode 找不到 iPhone
**现象**：设备列表中没有显示 iPhone

**解决**：
1. 确保 iPhone 已解锁并信任电脑
2. 检查 USB 线是否为数据线（非充电线）
3. 重启 iPhone 和 Xcode
4. 尝试更换 USB 端口

### 问题 2：签名错误 "Failed to create provisioning profile"
**现象**：编译时报签名错误

**解决**：
1. 修改 Bundle Identifier 为唯一值
2. 确保 Apple ID 已添加到 Xcode 偏好设置
3. Xcode → Preferences → Accounts → 添加 Apple ID

### 问题 3：应用闪退
**现象**：安装后打开立即闪退

**解决**：
1. 检查 iPhone iOS 版本是否 ≥ 18.2
2. 在 Xcode 查看崩溃日志
3. 确保相册权限描述在 Info.plist 中

### 问题 4："不受信任的开发者"
**现象**：首次安装后无法打开应用

**解决**：
1. iPhone → 设置 → 通用 → VPN与设备管理
2. 找到你的 Apple ID，点击信任

### 问题 5：编译错误 "Command SwiftCompile failed"
**现象**：Xcode 编译失败

**解决**：
1. Product → Clean Build Folder (Shift+Cmd+K)
2. 重新编译 (Cmd+B)
3. 确保 Xcode 版本 ≥ 16.2

### 问题 6：TestFlight 邀请收不到
**现象**：测试人员未收到邀请邮件

**解决**：
1. 检查邮箱垃圾邮件
2. 确保邮箱与 Apple ID 关联
3. 直接在 TestFlight App 中使用兑换码

---

## 快速参考命令

```bash
# 打开项目
open PhotoSwipeCleaner.xcodeproj

# 清理构建
xcodebuild clean -project PhotoSwipeCleaner.xcodeproj -scheme PhotoSwipeCleaner

# 构建（不运行）
xcodebuild build -project PhotoSwipeCleaner.xcodeproj -scheme PhotoSwipeCleaner

# 运行到连接的设备
xcodebuild -project PhotoSwipeCleaner.xcodeproj -scheme PhotoSwipeCleaner -destination 'platform=iOS,name=你的iPhone名称'
```

---

## 相关文档

- [PHASE1_SUMMARY.md](./PHASE1_SUMMARY.md) - 功能开发总结
- [Apple Developer 文档](https://developer.apple.com/documentation/xcode)
- [App Store 审核指南](https://developer.apple.com/app-store/review/guidelines/)

---

**最后更新**：2024年
**维护者**：开发团队
