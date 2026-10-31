# BreakLoop 软件工程规范与架构宪章 (Constitution)

## 1. 核心价值观与原则

### 1.1 原生性与超轻量 (Native & Lightweight)
- 语言框架：纯原生 Swift 5.9+、SwiftUI + AppKit。
- 零多余依赖：除了系统框架（SwiftUI、AppKit、Charts、WidgetKit）与基础系统 API（Carbon HotKeys、CGEventSource）外，坚决保持零外部三方依赖。
- 资源占用：闲置时 CPU 接近 0.0%，内存常驻小于 35 MB。

### 1.2 极简二元状态机 (Binary State Flow)
- 状态哲学：**工作就是工作，休息就是休息，不工作就是休息，待机就是彻底停止计时**。
  - `working`：倒计时，专注工作。
  - `resting`：正计时，身心放松。
  - `standby`：待机出口，所有计时器销毁，不计时间。
- 严禁引入模棱两可、让用户费解的多余操作（如暂停、继续、跳过等混合状态）。

### 1.3 真实客观与时间回溯 (Objective Tracking & Backtracking)
- 基于 `Date` 差值计算，杜绝每秒递减引起的系统调度或休眠漂移。
- 键鼠空闲超时或锁屏/休眠时自动进入 `standby`，结束时间必须回溯至**最后一次实际键鼠活动的时间**，绝不记录虚假时长。

### 1.4 Apple Music 现代扁平视觉美学 (Design Aesthetics)
- 遵循 macOS Human Interface Guidelines（HIG）。
- 告别冷硬灰色框线，采用大留白、柔和通透的微渐变背景与半透明毛玻璃材质（Ultra-thin Material）。
- 统一符号：
  - **工作（Working）**：优雅书本 `book.fill` / `book.closed.fill`。
  - **休息（Resting）**：温暖咖啡 `cup.and.saucer.fill`。
  - **待机（Standby）**：宁静绿叶 `leaf.fill`。
- 彻底摒弃跳秒焦虑，全平台仅以**分钟级**展示（如 `25m`、`5m`）。

### 1.5 标准 macOS App 架构 (Standard App Architecture)
- 具有独立的 Dock 存在与应用生命周期。
- 点击红叉 `X` 仅隐藏窗口（Hide on Close），后台计时与到点提醒照常运作。
- 菜单栏作为高频快捷入口；主窗口作为一体化仪表盘与数据中心。
