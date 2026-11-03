# Glimpse / PhotoSift

## 产品定位（2026-11-01）

- **Glimpse**：iOS 相册 App，滑动清理、相册整理与本地智能分组。
- **PhotoSift（拾图）**：macOS 本地照片分类整理工具，CLI 命令为 `photosift`，原生界面沿用现有 GlimpseMac 构建目标。

两个产品暂在同一仓库，不复制底层代码；CLI 与原生界面不共享任务记录。PhotoSift 只做“分析照片 → 检查计划 → 确认加入相册”，不引入插件或工作流框架。现有 iOS 官网源码见 [website/](website/README.md)。

`photosift` 与现有 `glimpse` 命令使用同一实现及运行目录；既有命令、进度、锁和相册名称保持不变，不迁移个人数据。当前命名是本地开发名称，未核查商标或域名。

本地照片整理项目，目前有三个独立入口。它们的任务记录不共享，不要把 CLI 进度当作原生 App 进度。

| 入口 | 当前用途 | 照片访问 | 构建要求 |
| --- | --- | --- | --- |
| macOS CLI PhotoSift（photosift） | 全图库分批分类、输出计划、确认后加入相册 | Photos Automation，临时导出 | Swift 6 + Command Line Tools，macOS 14+ |
| macOS App GlimpseMac | 纯 AppKit 界面：全图库分批、模型状态、分类方案、网格复核、相册映射和撤销 | PhotoKit | 完整且兼容系统的 Xcode，macOS 15+ |
| iOS App PhotoSort | 滑动清理、相册整理和本地智能分组 | PhotoKit | 完整 Xcode，iOS 18.2+ |

CLI 与原生 App 分别交付内部预览包，下载后运行都不需要 Xcode；从源码构建原生 App 仍需要完整 Xcode。安装步骤见 [CLI 安装说明](docs/cli-install.md) 和 [原生 App 安装说明](docs/native-install.md)。发布验收契约见 [功能说明](docs/functionality.md)；原生设计见 [macOS Spec](docs/macos-local-photo-classification-spec.md)。开发周期遵循 [AGENTS.md](AGENTS.md)：先资料、再失败测试、最小实现、最终核对。当前格式不做向后兼容或迁移。

## 原生 App 一行安装

GlimpseMac 适用于 Apple Silicon Mac（macOS 15+）。在「终端」里运行：

```sh
curl -fsSL https://raw.githubusercontent.com/sogud/glimpse/master/install.sh | sh
```

脚本会下载最新版本（包括预览版），校验 SHA-256，把 `GlimpseMac.app` 装到「应用程序」（没有写入权限时装到 `~/Applications`）。用这种方式安装不会弹出 Gatekeeper 拦截。指定版本：`curl -fsSL … | VERSION=v0.4.0 sh`；卸载：`curl -fsSL … | sh -s -- --uninstall`（不删任务记录和设置）。安装前可以先看看[脚本内容](install.sh)。CLI 仍按 [CLI 安装说明](docs/cli-install.md) 手动安装。

<details>
<summary>手动安装 / 提示「无法验证开发者」</summary>

GlimpseMac 只做了本地临时签名，没有经过 Apple 公证，所以用浏览器下载后第一次打开会被拦截。

1. 在 [Releases](https://github.com/sogud/glimpse/releases) 下载 `GlimpseMac-<版本>-macos-arm64.zip`，解压后把 `GlimpseMac.app` 拖进「应用程序」。
2. 方法一：在终端运行
   ```sh
   xattr -dr com.apple.quarantine /Applications/GlimpseMac.app
   ```
3. 方法二：先双击打开一次，然后进入 **系统设置 → 隐私与安全性**，在下方找到「已阻止打开 GlimpseMac」，点 **仍要打开**，再输入密码确认。

</details>

## CLI 使用

先在 LM Studio 中启动本地服务并加载视觉模型，例如已安装的 Qwen3-VL。CLI 不安装模型、不自动启动服务。可先查询服务报告的模型，不访问照片、不创建任务记录：

    rtk swift run photosift photos models --json

`models` 可指定 `--endpoint`，仅支持本机回环地址。结果是服务返回的模型 ID，不代表已经验证视觉能力或实际加载状态；服务不可用时返回错误，不自动启动或下载模型。

    rtk swift run photosift photos status --json
    rtk swift run photosift photos classify-next --limit 10

classify-next 从已保存的稳定 Photos ID 继续扫描，单批最多检查 10 个图库项目；视频或无法导出的项目也占名额。同一用户同时只允许一个写进程，即使运行目录不同。classify-selection 处理手选照片，同样记录结果。失败或跳过项目可显式重新排队：

    rtk swift run photosift photos retry failed
    rtk swift run photosift photos retry skipped

默认数据在 ~/Library/Application Support/Glimpse/CLI。GLIMPSE_HOME 可指定隔离目录；不读取或迁移旧版个人进度文件。

默认端点是 http://127.0.0.1:1234/v1，只允许本机回环地址，拒绝 HTTP 重定向。未指定 --model 时按模型名称优先选择 Qwen3-VL/vision/vl；这不是视觉能力检测，多个模型或特殊名称建议显式指定：

    rtk swift run photosift photos classify-next --limit 10 --model qwen/qwen3-vl-4b --json

每张图片只发送一次分类请求，同一次响应决定普通照片/截图及具体分类。不自动降级重发；模型必须能接受图片和结构化输出。服务返回的实际错误会保留，不能仅凭 HTTP 400 判断是视觉模块或结构化输出不兼容。

流程是：Photos 临时导出副本 → sips 转成最长边 1024 px 的 JPEG → 本机 LM Studio → 保存 JSON 计划 → 正常完成或抛出错误时清理临时图片。导出过程可能下载 iCloud 原图；强制终止进程可能留下临时文件。分析不会创建分类相册、移动或删除照片。

计划保存在运行目录的 Plans/，也可以用 --output 指定新路径。已有文件不会覆盖。先保存计划，再保存批次进度。

检查输出或 JSON 计划后，再显式应用：

    rtk swift run photosift photos apply "<plan.json>"

命令会验证计划里的分类 ID、名称、方案和照片 ID，再显示相册清单，输入 yes 后才写入。首次访问需要允许终端控制「照片」。只向 Glimpse 文件夹下的“普通照片·分类”“截图·分类”或统一的“待删除”相册添加照片；原照片不移动、不删除。“待删除”只是一条需要人工复核的建议。

相册按顺序写入，每个相册的进行中/已确认结果保存在 Receipts/。中途退出或失败后，重新 apply 同一计划会跳过已确认的相册，继续未知或尚未写入的相册；添加操作会检查已有成员。修改已开始写入的计划会被拒绝。CLI 不自动回滚，也不提供删除或撤销。

## 进度含义

photos status [--json] 只读本机批处理记录，不访问 Photos、不连接模型，也不查询图库总数：

- classified：成功得到分类；不代表已加入相册。
- needsReview：分析完成，但模型未确定分类。
- retryPending：模型分析失败，后续 classify-next 再尝试；单次运行不重发。
- failed：已失败三次，停止自动重试。
- skipped：视频或 Photos 未能导出的项目；retry skipped 可重新排队。
- excludedFromNextBatch：下次按 ID 跳过的总数，不是成功分类数量。
- scanComplete：上一次扫描到达末尾，不意味着全部分类或写入成功，也不反映后来新增照片。
- receipts：计划 ID、确认成员数、已确认/结果未知/尚未处理相册数和完成状态；不输出照片详情。具体资源记录保存在私人回执文件中。

## 开发与验证

    rtk proxy bash scripts/check.sh
    rtk proxy bash scripts/check-appkit.sh
    rtk swift build -c release --product photosift

检查使用合成计划、临时文件和临时本机 HTTP 服务，不访问个人 Photos 或 LM Studio。check-appkit.sh 操作原生控件，验证新建任务、复核、缩略图刷新和取消写入；加 --preview 可查看合成照片网格。原生应用在 PhotoSort.xcodeproj 内选择 PhotoSort 或 GlimpseMac scheme；这些组件检查不等于完整 App 和真实 PhotoKit 流程验收。

## License

本仓第一方代码采用 [MIT License](LICENSE)。第三方代码与素材保留各自的许可和署名，根许可证不替代其原有条款。
