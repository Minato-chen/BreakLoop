# 特性规范：Apple Music 风格视觉重构、书本/咖啡符号更迭与小组件终极修复

## 1. 业务目标
将 BreakLoop 的主界面全面重构为类似 Apple Music 的扁平通透、大留白、柔和弥散渐变的现代 macOS 设计。将“大脑”符号更换为“书本(工作)”与“咖啡(休息)”。精简重构菜单栏右键/点击交互，并彻底排查解决 macOS 原生系统小组件嵌入与注册问题。

## 2. 界面与交互规范 (Apple Music 风格)
- **色调与光感**：
  - 去除厚重灰边与生硬线条，采用半透明薄层材质（`.ultraThinMaterial`）与纯净背景；
  - 仪表盘中央：工作时采用温暖暖阳/琥珀金微渐变，休息时采用清爽晨露/薄荷绿微渐变。
- **符号标准化**：
  - 工作状态：`book.closed.fill` / `book.fill`。
  - 休息状态：`cup.and.saucer.fill`。
  - 待机状态：`leaf.fill`。
- **时间排版**：
  - 严禁出现跳秒数字，统一采用 Apple Rounded 字体展示 `25m` / `5m`。
  - 核心操作键采用优雅大胶囊按钮（类似 Apple Music 播放键）。

## 3. 菜单栏右键与主菜单重构
- 顶部常驻轻量状态标识：`[📖 专注中 18m]` 或 `[☕️ 休息中 3m]` 或 `[🌿 待机就绪]`。
- 快捷二元动作：
  - 工作时：`☕️ 去休息`
  - 休息时：`📖 开始工作`
  - 任何时：`🌙 待机 (停止计时)`
- 快捷操作：
  - `打开 BreakLoop 仪表盘... (⌘O)`
  - 快速切换预设方案
  - `退出 BreakLoop (⌘Q)`

## 4. 系统小组件彻底修复与注册 (WidgetKit)
- 确保 Xcode 正确配置 `Embed Foundation Extensions` 拷贝规则，确保小组件 `.appex` 位于 `BreakLoop.app/Contents/PlugIns/`。
- 确保 Info.plist 中的 `NSExtension` 包含 `com.apple.widgetkit-extension`。
- 执行本地 `lsregister` 与系统缓存强制刷新，保证小组件出现在 macOS “编辑小组件”列表中。
