# Ariadne

原生 macOS 聚焦搜索（Spotlight）风格开发项目快速启动器 —— 一键呼出所有 VS Code 项目，键盘快速筛选，用 **VS Code** 或 **Kitty** 直接打开对应项目目录。

A native macOS Spotlight-style launcher for VS Code projects with instant Kitty terminal directory launch.

---

## 核心功能 / Features

- **全局快捷键唤起（支持组合键与双击修饰键）**
  - 默认快捷键 `⌥ Space`（基于 Carbon `RegisterEventHotKey`，无需辅助功能权限）。
  - 支持绑定 **双击 Command（`⌘ ⌘`）**、双击 Option（`⌥ ⌥`）、双击 Control（`⌃ ⌃`）、双击 Shift（`⇧ ⇧`），可在设置中直接双击录制或点击预设切换（双击修饰键需授予“辅助功能”权限以避免 `⌘C`/`⌘V` 误触）。
- **原生 Spotlight 悬浮面板**
  - 非激活悬浮毛玻璃窗口（`NSPanel` + `NSVisualEffectView`），支持全屏应用空间，支持中文输入法（IME 选词不误触关闭或提交）。
- **完整发现 VS Code 所有项目**
  - `state.vscdb`（`history.recentlyOpenedPathsList` 最近打开顺序）
  - `workspaceStorage/*/workspace.json`（历史打开过的所有项目目录与 `.code-workspace`）
  - `storage.json`（旧版本兼容）
  - VS Code Project Manager 扩展（`projects.json`）
  - 支持开启 VS Code Insiders 与自定义扫描目录，并显示项目当前 Git 分支。
- **VS Code + Kitty 无缝联动**
  - `↓` / `↑`（或 `⌃N` / `⌃P`）选择项目
  - `⏎`：用 **VS Code** 打开项目（可在设置修改为默认打开 Kitty 或两者同时打开）
  - `⌘ ⏎`：用 **Kitty** 直接打开到对应项目目录（`.code-workspace` 自动解析到对应文件夹）
  - `⌥ ⏎`：同时在 **VS Code** 和 **Kitty** 中打开
  - `Tab` / `⌘K`：打开完整动作菜单（VS Code / Kitty / Both / 在 Finder 中显示 / 复制路径）
  - `⌘P`：置顶 / 取消置顶常用项目
  - `⌘1`–`⌘9`：快速打开前 9 个项目
  - `⌘,`：打开设置界面
- **Kitty 打开模式可选**
  - **New OS Window (默认)**：通过 `kitty.app` 原生打开新窗口并直接 `cd` 到项目目录，无需配置远程控制
  - **New Tab (Remote Control)**：通过 `kitty` 远程控制 socket 在当前窗口新建标签页（失败自动回退为新窗口）
  - **Single Instance CLI**：通过 `kitty --single-instance --directory` 启动
- **开机自启 & 菜单栏常驻**
  - 支持 `SMAppService` 登录时自动启动，菜单栏图标随时管理。

---

## 从 GitHub Releases 下载使用 / Download

1. 前往本仓库的 **[Releases](../../releases)** 页面，下载最新的：
   - `Ariadne-*-macOS-universal.dmg`（推荐，包含 Apple Silicon `arm64` 与 Intel `x86_64` 通用二进制）
   - 或 `Ariadne-*-macOS-universal.zip`
2. 打开 `.dmg`，将 **Ariadne.app** 拖入 `/Applications`（应用程序）文件夹。
3. **首次打开说明（未公证的 Ad-hoc 签名版本）：**
   如果 macOS Gatekeeper 提示无法验证开发者，可以右键 `Ariadne.app` -> **打开**，或在终端执行一次：
   ```bash
   xattr -cr /Applications/Ariadne.app
   ```

---

## GitHub Actions 自动打包与发布 / CI & Release

仓库已内置两个 GitHub Actions 工作流：

- **`.github/workflows/ci.yml`**
  - 在所有分支 `push` 和 `pull_request` 时在 `macos-latest` 上运行 `swift test` 并验证打包产物（`.dmg` / `.zip`）。
- **`.github/workflows/release.yml`**
  - **推送到 `main` 分支**：自动运行测试、构建 Universal `.app` / `.dmg` / `.zip` 并发布/更新 `latest` Release。
  - **推送版本 Tag（如 `git tag v0.1.0 && git push origin v0.1.0`）**：自动创建对应版本的正式 Release。
  - **手动触发（`workflow_dispatch`）**：在 GitHub Actions 页面点击 **Run workflow**，输入版本号即可打包发布。

---

## 本地构建与测试 / Local Development

系统要求：macOS 13.0+，Xcode 15+ / Swift 5.9+。

```bash
# 运行单元测试
swift test

# 运行调试版
swift run Ariadne

# 打包 Universal .app、.dmg 和 .zip 到 dist/ 目录
./scripts/package.sh
```
