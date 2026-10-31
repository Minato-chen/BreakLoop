import SwiftUI
import AppKit

/// 独立顶级大类：快捷键管理与速查中心
public struct ShortcutsView: View {
    public init() {}
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // 1. 顶部标题区
                headerSection
                
                Divider()
                
                // 2. 全局生效状态说明卡片
                statusBanner
                
                // 3. 快捷键详细列表卡片
                shortcutsListSection
                
                // 4. 常见问题与小提示
                tipsSection
            }
            .padding(24)
            .frame(maxWidth: 680)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
    }
    
    // MARK: - 顶部标题
    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 26))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("快捷键中心")
                    .font(.system(size: 18, weight: .bold))
                Text("全局快捷键支持在 macOS 任意前台应用或全屏工作流中一键调度循环")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - 运行状态横幅
    private var statusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("系统级全局热键处于常驻激活状态")
                    .font(.system(size: 13, weight: .semibold))
                Text("无需聚焦 BreakLoop 主窗口，在任何应用、终端或全屏 IDE 下均可直接按下生效")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - 快捷键详细列表
    private var shortcutsListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("核心操作快捷键")
                .font(.system(size: 14, weight: .bold))
            
            VStack(spacing: 12) {
                shortcutRow(
                    keys: ["⌥ Option", "⇧ Shift", "S"],
                    title: "开始专注 / 进入下一轮",
                    description: "处于待机状态时立即开始首个专注块；在休息或专注进行中直接推进至下一个流程阶段"
                )
                
                Divider()
                
                shortcutRow(
                    keys: ["⌥ Option", "⇧ Shift", "R"],
                    title: "立即休息 / 开启放松",
                    description: "无论当前处于什么状态，立即跳入休息阶段，强制让双眼与身体放松"
                )
                
                Divider()
                
                shortcutRow(
                    keys: ["⌥ Option", "⇧ Shift", "⎋ Esc"],
                    title: "随时挂起 / 进入待机",
                    description: "需要离开工位、接听电话或临时开会时，一键挂起所有倒计时与提醒机制"
                )
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    private func shortcutRow(keys: [String], title: String, description: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.8)
                        )
                }
            }
        }
    }
    
    // MARK: - 贴士
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("使用贴士")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                    .padding(.top, 1)
                Text("快捷键采用 Option + Shift 组合键前缀，有效规避了与 Xcode、VS Code、浏览器等常用开发者软件的冲突。即使关闭 BreakLoop 主窗口，快捷键在后台依然保持生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
