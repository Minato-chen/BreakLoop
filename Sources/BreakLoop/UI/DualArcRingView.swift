import SwiftUI

/// Apple 风格双弧流转比例表盘圆环组件
/// 广泛应用于 日 / 周 / 月 / 年 四大时间维度的统计、回顾与对比
public struct DualArcRingView: View {
    public let workMinutes: Double
    public let restMinutes: Double
    public let maxMinutes: Double       // 满环刻度（例如 60.0，480.0，160*60）
    public let size: CGFloat            // 尺寸直径
    public let lineWidth: CGFloat       // 线宽
    public var showTrack: Bool = true
    
    public init(
        workMinutes: Double,
        restMinutes: Double,
        maxMinutes: Double = 60.0,
        size: CGFloat = 20,
        lineWidth: CGFloat = 2.5,
        showTrack: Bool = true
    ) {
        self.workMinutes = max(0, workMinutes)
        self.restMinutes = max(0, restMinutes)
        self.maxMinutes = max(1.0, maxMinutes)
        self.size = size
        self.lineWidth = lineWidth
        self.showTrack = showTrack
    }
    
    // 专注占比
    private var rawWorkRatio: Double {
        min(1.0, workMinutes / maxMinutes)
    }
    
    // 休息占比
    private var rawRestRatio: Double {
        min(max(0.0, 1.0 - rawWorkRatio), restMinutes / maxMinutes)
    }
    
    // 最小可见圆角胶囊端点（防极小时间看不清）
    private var workFraction: Double {
        if workMinutes > 0 {
            return max(0.045, rawWorkRatio)
        }
        return 0.0
    }
    
    private var restFraction: Double {
        if restMinutes > 0 {
            return max(0.045, rawRestRatio)
        }
        return 0.0
    }
    
    public var body: some View {
        ZStack {
            // 1. 实体微凹槽底轨（Apple Watch 级 Inset Track，暗色微立体，即便 0 活跃也清晰规整防空洞）
            if showTrack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.12),
                                Color.primary.opacity(0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
            }
            
            // 2. 专注弧（Apple 专注蓝 -> 紫绀渐变，顺时针从 12 点钟开始）
            if workFraction > 0 {
                Circle()
                    .trim(from: 0.0, to: min(1.0, workFraction))
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.52, blue: 1.0), // #0A84FF
                                Color(red: 0.35, green: 0.38, blue: 0.95)  // #5856D6
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(red: 0.05, green: 0.52, blue: 1.0).opacity(0.35), radius: max(1.0, lineWidth * 0.4))
            }
            
            // 3. 休息弧（Apple 薄荷翡翠绿 -> 晨光青，紧接在专注弧后顺时针绘制）
            if restFraction > 0 {
                let startTrim = min(0.95, workFraction)
                let endTrim = min(1.0, startTrim + restFraction)
                Circle()
                    .trim(from: startTrim, to: endTrim)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.82, blue: 0.38), // #30D158
                                Color(red: 0.25, green: 0.85, blue: 0.72)  // Mint Cyan
                            ],
                            startPoint: .bottomTrailing,
                            endPoint: .topLeading
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(red: 0.18, green: 0.82, blue: 0.38).opacity(0.35), radius: max(1.0, lineWidth * 0.4))
            }
        }
        .frame(width: size, height: size)
    }
}
