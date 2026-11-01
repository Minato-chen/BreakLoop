# BreakLoop (专注循环)

<p align="center">
  <img src="Sources/BreakLoop/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="BreakLoop Icon" width="128" height="128" />
</p>

<p align="center">
  <strong>专为 macOS 打造的高质感模块化专注与工休循环健康管理工具</strong>
</p>

<p align="center">
  <a href="https://github.com/Minato-chen/BreakLoop/releases"><img src="https://img.shields.io/github/v/release/Minato-chen/BreakLoop?color=brightgreen&label=Release" alt="Release Version" /></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2013.0+-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%2F%20Intel-success" alt="Architecture" />
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="License" />
</p>

---

## 💡 为什么选择 BreakLoop？

传统的番茄钟与休息软件通常存在以下痛点：
- **模式机械死板**：仅支持单调的「25分钟工作 - 5分钟休息」二元交替，无法适应个性化工作流（如：20-20-20 护眼、深度攻坚长周期、多级阶梯休息等）；
- **挂机污染数据**：锁屏离开或进入屏保后，软件依旧空跑，将离座摸鱼误计为专注，导致统计失真；
- **打断体验生硬**：灵感正盛时被强制全屏弹窗或倒计时打断，或在休息时必须盯着倒数，无法自主掌控节奏；
- **统计图表粗糙**：缺乏宏观全景，难以直观洞察一周甚至全年的工休节奏比例。

**BreakLoop** 重新定义了人与电脑的节奏协作：
它不仅支持**任意工休模块自由拼装流水线**，还拥有类似 **Apple Watch 运动圆环** 的双弧流转比例表盘与 **7×24 小时微环热力图**，并具备**屏幕保护感知与离座时间自动回溯扣除**能力，是一款兼具原生视觉美感与扎实工程设计的 macOS 效率神器。

---

## ✨ 核心特性

### 1. 🎛️ 专注仪表台 (Focus Dashboard)
- **实体凹槽发光流转表盘**：Apple Watch 级设计，高精度平滑渲染当前模块倒计时/正计时进度与双弧比例。
- **直观流转控制**：支持一键开始、暂停/继续、快速跳至下一步、一键待机以及整轮重置。
- **持久化循环轮数**：方案切换或重启软件不丢失今日累计轮数，清晰度量全天的专注成就。
- **流水线步骤卡片**：可视化展示当前循环链条，支持随时点击卡片任意跳转到指定步骤。

### 2. 🔀 模块化流水线方案管理 (Pipeline Engine)
- **任意步骤自由拼装**：自由组合工休环节（例如：*20m 专注 ➔ 20s 远眺 ➔ 30m 攻坚 ➔ 5m 走动 ➔ 15m 运动大休*）。
- **专注与多元休息支持**：
  - **专注模块**：严格倒计时，营造沉浸心流。
  - **固定倒计时休息**：到点温柔提示，支持稍后提醒延时。
  - **自由正计时休息**：专门为 20-20-20 护眼法则打造，时间自然递增，到达建议下限后温和提醒，不打扰、不强制中断。
- **稍后提醒专注加时 (Snooze)**：工作提醒弹出时可一键选择「稍后 5 分钟」，专注自动延长 5 分钟并完整保留后续全部休息时间。
- **进行中方案安全锁定**：方案运行中自动锁定编辑防误触，标题下方轻量提示「运行中无法更改」，进入待机即可随时调整。
- **极简打断恢复策略**：针对手动进入待机或系统息屏休眠，独立设定恢复行为（*重置本步 / 断点续传 / 推进至下一步 / 重置整轮*）。

### 3. 📊 双弧流转比例圆环与专注热力图 (Dual-Arc Heatmap)
- **双弧比例圆环 (`DualArcRingView`)**：深蓝（专注）与青绿（休息）双弧在环形轨道端对端闭环流转，内嵌物理凹槽质感。
- **四维全景深度洞察**：
  - **周视图**：7×24 小时微圆环矩阵（每格代表 60 分钟标准环），鼠标悬停实时查看工休时长、工休比与具体起止时段。
  - **日视图**：24 小时对比环轨与流水账时间轴。
  - **月视图**：日历格子以每日环状图呈现工休强度，支持点击穿透钻取日视图。
  - **年视图**：12 个月度宏观对比圆环，支持点击穿透钻取月视图。
- **数据完全自主掌控**：支持一键导出 CSV 原始数据明细，方便做二次分析。

### 4. 🔔 优雅提醒与音效系统 (Alerts & Sound Engine)
- **原生磨砂毛玻璃浮窗**：自适应窗口高度，居中显示自定义文案，长文本自然折行绝不截断。
- **多样化提醒形式**：弹窗与声音、仅声音、仅弹窗、完全静音随心选择。
- **全局声音与文案预设**：为专注与休息独立设定默认提示音与提醒语句，支持一键覆盖同步至全部现有方案。
- **长音频防疲劳保护**：
  - 提示音连续重复播放（1~5 次），避免因走开遗漏；
  - 超过时长上限（10~15 秒）自动截断，并在末尾 2 秒平滑淡出渐弱。
- **自定义音频库**：支持导入个人音频（`.wav`, `.mp3`, `.m4a`, `.aiff`, `.caf`），独立调节音量。

### 5. 🖥️ 屏保感知与离开自动回溯 (Smart Idle & Standby)
- **系统事件原生监听**：实时监听 macOS 屏幕保护（`com.apple.screensaver.didstart`）与键鼠无操作闲置。
- **离座时间精准回溯扣除**：因离开自动转入待机时，**自动扣除离开期间的时间**，真实还原有效工休。
- **防挂机超时保护**：暂停过久（可配 3m / 5m / 10m / 15m / 从不）自动转入待机，防止遗忘挂机。

### 6. 🚀 菜单栏驻留与桌面小组件 (Menu Bar & Widget)
- **原生 Menu Bar 常驻**：响应式即时渲染，模式切换 0 延迟变色，实时显示当前步骤名与倒计时/正计时（首分钟显示 `> 0m`）。
- **快捷弹出面板**：在菜单栏中快速掌控进度、启停与切换方案。
- **macOS 桌面小组件**：WidgetKit 深度原生集成，随时在桌面上掌控工休节拍。

---

## 📥 下载与安装 (GitHub Release)

### 方式一：直接下载预编译版本（推荐）

1. 访问 GitHub Releases 页面下载最新版本：  
   👉 **[GitHub Releases - BreakLoop 最新发布](https://github.com/Minato-chen/BreakLoop/releases/latest)**
2. 下载 `BreakLoop-2.0.0.dmg` 或 `BreakLoop-2.0.0.zip`。
3. 双击解压并拖拽 `BreakLoop.app` 到 **访达 -> 应用程序 (Applications)** 目录即可。

> **提示（首次打开 macOS 提示未签名或无法验证开发者）**：  
> 若提示无法打开，请在访达的「应用程序」中找到 BreakLoop，**右键点击 -> 选择「打开」**，并在弹出的确认对话框中点击「打开」即可，或在「系统设置 -> 隐私与安全性」底部点击「仍要打开」。

---

## 🔒 隐私与安全性

- **100% 本地纯离线运行**：所有方案配置、计时记录与统计数据均保存在本地沙盒，绝不上传任何服务器。
- **零外部分析与打点**：无第三方 SDK、无广告、无用户行为追踪。
- **仅极简版本检查**：仅在设置中开启自动检查更新或手动点击时，通过官方 GitHub Releases API 检索是否有最新版本。

---

## 🛠️ 技术栈与架构设计

- **Language**：Swift 5.9+
- **Frameworks**：SwiftUI, AppKit, WidgetKit, Combine, AVFoundation, UniformTypeIdentifiers
- **Architecture**：
  - `TimerEngine`：单向数据流计时核心，高精度时间差补偿与离座回溯保护。
  - `IdleMonitor`：底层 IOKit / CoreGraphics 闲置捕获与 DistributedNotificationCenter 屏保事件监听。
  - `PresetStore` / `SessionStore`：本地持久化与数据完整性校验。
  - `DualArcRingView`：高性能声明式双弧几何绘制引擎。
- **Tests**：内置 **22 项完整单元测试覆盖**，涵盖崩溃恢复、打断续传、回溯扣除、循环调度、加时延后、正计时向下取整与声音截断规则。

---

## 💻 源码构建与开发

### 环境要求
- macOS 13.0 (Ventura) 或更高版本
- Xcode 15.0 或更高版本

### 本地编译

1. **克隆仓库**
   ```bash
   git clone https://github.com/Minato-chen/BreakLoop.git
   cd BreakLoop
   ```

2. **运行单元测试**
   ```bash
   swift test
   ```

3. **使用 xcodebuild 编译 Release 产物**
   ```bash
   xcodebuild -scheme BreakLoop -configuration Release -destination 'platform=macOS' build
   ```
   编译产物位于 `Build/Products/Release/BreakLoop.app`。

---

## 🤝 贡献与反馈

非常欢迎提交 Issue 或 Pull Request 来帮助 BreakLoop 变得更好！
- 提交 Bug 反馈或功能建议：[GitHub Issues](https://github.com/Minato-chen/BreakLoop/issues)
- 欢迎给项目点一个 ⭐️ **Star** 支持我们的持续打磨！

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
