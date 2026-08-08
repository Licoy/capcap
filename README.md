<p align="center">
  <img src="images/app-banner.png" alt="capcap 应用横幅" width="760" />
</p>

<h1 align="center">capcap</h1>

<p align="center">
  macOS 上最顺手的菜单栏截图工具：双击 <code>⌘</code> 即刻截图、标注、长截图、美化、钉图和上传。
</p>

<p align="center">
  <a href="https://github.com/Licoy/capcap/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Licoy/capcap?style=flat-square"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/Licoy/capcap/releases/latest">下载</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="https://github.com/Licoy/capcap/issues">Issues</a>
</p>

<p align="center">
  <sub>本仓库为 <a href="https://github.com/realskyrin/capcap">realskyrin/capcap</a> 的 fork 二开维护版（Licoy/capcap）</sub>
</p>

**macOS 上最顺手的截图工具。** 双击 `⌘` 即开即用——窗口一点就贴边、选区像素级精准、长截图边滚边拼，再用浮动编辑器一气呵成完成标注与美化。常驻菜单栏，不占 Dock，无遥测、无订阅、零第三方依赖；想要一键拿到图片云端链接，自己接入图床即可。

<p align="center">
  <img src="images/editor.png" alt="capcap 标注编辑器——箭头、序号、马赛克、高亮和文字层叠在截图上，所有操作集中在一个浮动工具栏中" width="760" />
</p>

<p align="center">
  <a href="https://github.com/Licoy/capcap/releases/latest"><b>下载最新版本</b></a> &nbsp;·&nbsp;
  macOS 14+ &nbsp;·&nbsp; Universal（Apple Silicon + Intel）
</p>

## 与原版的区别

本 fork 基于上游 [realskyrin/capcap](https://github.com/realskyrin/capcap) 进行二开维护，主要差异：

| 项 | 本仓库（Licoy/capcap） | 上游（realskyrin/capcap） |
|----|------------------------|---------------------------|
| Bundle ID | `com.github.licoy.capcap.desktop` | `cn.skyrin.capcap` |
| 更新 / 发布源 | [Licoy/capcap Releases](https://github.com/Licoy/capcap/releases) | 上游 GitHub Releases |
| 文档语言 | 仅中文 + 英文 README | 多语言 README |
| 发布签名 | CI 使用自签证书（GitHub Actions Secrets） | 上游自签流程 |
| 版本基线 | 从 `v1.0.0` 起作为本 fork 独立版本线 | 上游独立版本线 |

说明：更换 Bundle ID 后，本构建与上游安装版是两套独立应用（权限、偏好不共享），可并行安装。

## 为什么选 capcap

- **一个快捷键，零学习成本。** 在任意 app 中双击 `⌘` 即刻唤起 capcap；也可以在设置中录制任何全局快捷键。
- **窗口一点即贴边，选区像素级精准。** 悬停窗口一点截取，或拖拽任意区域，多显示器全量支持，按 Retina 原生分辨率输出。
- **真正可二次编辑的标注。** 箭头、序号、文字、马赛克、高亮笔、画笔——放下之后还能拖、能转、能撤销，所见即所改。
- **长截图边滚边拼。** 在选区内滚动，实时预览拼接结果，合并后继续在同一个编辑器里改。
- **一键美化与钉图。** 渐变背景、桌面壁纸背景、圆角、阴影、内边距随手调；或把成图钉在所有窗口之上做对照。
- **Finder 图片也能直接编辑。** 在 Finder 中选中一张图片，按下同一个快捷键即可载入编辑器，原文件不会被改动。
- **菜单栏历史一键复用。** 最近截图和取色都在菜单栏，再次复制只需一次点击；完全本地、数量可配置。
- **一键上传到自己的图床。** 可选：在设置里配置好腾讯云 COS、七牛云 Kodo 或阿里云 OSS，点一下编辑器里的上传按钮，公网链接直接进剪贴板。密钥只保存在本机。
- **纯 AppKit 构建。** 没有 SwiftUI、Electron，也没有遥测。小、快、像 macOS 该有的样子。

## 功能特性

- **直接编辑已有图片**：在 Finder 中选中一张图片文件，再触发截图快捷键，capcap 会跳过截图，直接把这张图载入标注编辑器。
- **快速区域/窗口截图**：拖拽任意区域，或悬停识别窗口后点击，自动贴合窗口边界。
- **多显示器支持**：在所有连接的屏幕上创建截图遮罩，并按 Retina 真实像素分辨率输出。
- **完整标注编辑器**：支持矩形、椭圆、箭头、画笔、高亮笔、马赛克、序号标注和文字。
- **标注可二次编辑**：可移动已有标注，调整颜色和尺寸；支持旋转、弯曲箭头/序号引线、修改文字、删除标注，以及撤销/重做。
- **长截图**：在选区内滚动时连续捕获画面，实时预览拼接结果，合并后继续编辑。
- **美化模式**：为截图添加圆角、柔和阴影、渐变背景、桌面壁纸背景和可调内边距。
- **取色器**：调用 macOS 取色器，复制颜色的 `#RRGGBB` 值，并写入历史记录。
- **钉在屏幕**：把当前截图作为可拖动浮窗置顶显示，方便对照参考。
- **保存或复制**：可保存为 PNG，或确认后把 PNG/TIFF 写入剪贴板；也可以取消不输出。
- **最近历史**：菜单栏历史子菜单显示截图缩略图和取色记录，方便快速再次复制；缓存数量可配置。
- **图床上传**：可选地把截图一键上传到腾讯云 COS、七牛云 Kodo 或阿里云 OSS，公网链接写入剪贴板。
- **自定义触发方式**：默认双击 `⌘`，也可在设置里录制全局快捷键。
- **菜单栏应用**：以 agent app 运行，不显示 Dock 图标。

## 环境要求

- macOS 14.0+
- 辅助功能权限：用于默认的双击 `⌘` 触发
- 屏幕录制权限：用于 ScreenCaptureKit 和屏幕内容捕获
- Finder 自动化权限：首次使用「编辑已选中的图片」时弹出

首次启动时，capcap 会打开设置窗口并展示权限状态。权限都授予后即可启动应用。

## 安装

从 [Releases](https://github.com/Licoy/capcap/releases/latest) 下载 `.dmg` 或 `.zip`，将 `capcap.app` 拖到「应用程序」。

### macOS 校验拦截

本 fork 的 CI 使用**自签证书**打包（非 Apple Developer ID）。若 macOS 弹出类似 `Apple 无法验证 “capcap” 是否包含恶意软件` 的提示，可对你信任的应用包移除 quarantine 标记后再重新打开：

```bash
xattr -dr com.apple.quarantine /Applications/capcap.app
```

如果你运行的是本地构建版本，把路径替换成实际位置即可，例如：

```bash
xattr -dr com.apple.quarantine ./build/capcap.app
```

只应对你信任的构建执行这个命令，例如本仓库下载的版本或你本地自行构建的版本。

## 从源码构建

```bash
# 构建并打包为 build/capcap.app
./scripts/bundle.sh
```

本地开发时，可以使用下面的脚本重新构建、关闭旧进程、启动新应用，并确认应用已运行：

```bash
bash scripts/rebuild-and-open.sh
```

如需打包可拖拽安装的 DMG：

```bash
scripts/package-dmg.sh
```

应用包会输出到 `build/capcap.app`；DMG 会输出到 `dist/`。

## 使用方法

1. 双击 `⌘ Command`，按下自定义快捷键，或从菜单栏选择 **截图**。
2. 悬停窗口并点击可截取窗口；也可以拖拽选择任意区域。
3. 使用浮动工具栏进行标注、取色、长截图、美化、保存、钉图、取消或确认。
4. 点击绿色对勾或按 `Enter` 复制最终图片到剪贴板；按 `Esc` 或点击 `x` 取消。

如果想编辑桌面上或 Finder 里已经存在的图片，先在 Finder 中点选一张图片文件，再触发同一个快捷键。

## 编辑器工具

| 工具 | 作用 |
|------|------|
| 矩形 / 椭圆 | 绘制描边形状，可选择颜色和线宽 |
| 箭头 | 绘制直线箭头；选中后可移动端点或弯曲箭头 |
| 画笔 | 绘制平滑的自由画笔线条 |
| 高亮笔 | 绘制半透明高亮，不会因重叠反复加深 |
| 马赛克 | 在敏感区域刷出像素化遮挡，可调整块大小 |
| 序号 | 添加自动递增的序号圆点；放置时拖拽可带出箭头 |
| 文字 | 添加可编辑单行文字，支持颜色和 10-100 pt 字号 |
| 取色器 | 选取屏幕任意颜色并复制 `#RRGGBB` |
| 撤销 / 重做 | 撤销或恢复编辑器操作 |
| 移动选区 | 选区完成后拖动整个截图区域 |
| 长截图 | 在选区内滚动并拼接画面，完成后继续编辑 |
| 美化 | 添加渐变或壁纸背景、圆角、阴影和内边距 |
| 保存 | 将当前结果保存为 PNG |
| 钉在屏幕 | 将当前结果置顶悬浮显示 |
| 上传 | 将当前结果上传至已配置的图床，并把公网链接复制到剪贴板 |
| 确认 | 将最终结果复制到剪贴板 |

## 发布说明（维护者）

推送 `v*` 标签会触发 GitHub Actions 自动编译并发布：

1. **生成自签证书**（只需一次）：

   ```bash
   scripts/generate-signing-cert.sh
   ```

2. **配置 GitHub Actions Secrets**（仓库 Settings → Secrets → Actions）：

   | Secret | 内容 |
   |--------|------|
   | `MACOS_CERTIFICATE` | `capcap-signing.p12.base64` 文件内容 |
   | `MACOS_CERTIFICATE_PWD` | `.p12` 导出密码 |
   | `MACOS_SIGNING_IDENTITY` | 证书 CN，默认 `capcap Self-Signed` |
   | `KEYCHAIN_PASSWORD` | 任意临时字符串 |

   详见 [scripts/signing/README.md](scripts/signing/README.md)。**不要**将 `.p12` 提交进仓库。

3. **打版本并触发构建**：

   ```bash
   # 写入 Info.plist 版本、commit、打 annotated tag vX.Y.Z
   ./bump.sh -v 1.0.0

   # 推送分支与 tag（或使用 -p 一并推送）
   git push origin HEAD && git push origin v1.0.0
   # 等价：./bump.sh -v 1.0.1 -p
   ```

## 项目结构

- `capcap/App/`：应用入口、AppDelegate 和 bundle 元数据
- `capcap/Capture/`：截图遮罩、选区、窗口检测、ScreenCaptureKit 捕获、长截图拼接、剪贴板和历史记录
- `capcap/Editor/`：标注模型、编辑画布、浮动工具栏、美化渲染、马赛克、长截图预览和钉图窗口
- `capcap/Trigger/`：双击 `⌘` 监听和自定义 Carbon 全局快捷键
- `capcap/UI/`：菜单栏控制器、toast、鼠标提示和工具提示
- `capcap/Settings/`：首次启动/设置窗口和偏好设置 UI
- `capcap/Upload/`：图床实现与上传进度提示
- `capcap/Utilities/`：默认值、本地化、更新检查和开机启动支持
- `scripts/`：编译检查、打包、重启运行、图标、签名和 DMG 辅助脚本

## 开发

```bash
# 对影响 Swift 构建的改动做快速编译验证
bash scripts/compile-check.sh

# 构建、重启并确认本地应用已运行
bash scripts/rebuild-and-open.sh
```

## 致谢

- 上游项目：[realskyrin/capcap](https://github.com/realskyrin/capcap)
- 感谢 Linux.do 社区在测试、反馈和讨论中的支持

## 第三方许可证

- [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) 使用 MIT License。详见 [ThirdParty/PermissionFlow/LICENSE](ThirdParty/PermissionFlow/LICENSE)。

## License

[MIT](LICENSE)
