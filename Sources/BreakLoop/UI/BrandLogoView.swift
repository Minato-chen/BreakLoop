import SwiftUI

/// 苹果风原生矢量品牌 Logo：双弧流转呼吸环（Dual-Arc Breathing Loop）
/// 融合 Apple 专注蓝（#007AFF -> #5856D6）与健康翡翠绿（#30D158 -> #34C759），兼具科技沉思与生命呼吸感
public struct BrandLogoView: View {
    public let size: CGFloat
    public var showGlow: Bool
    
    public init(size: CGFloat = 20, showGlow: Bool = true) {
        self.size = size
        self.showGlow = showGlow
    }
    
    public var body: some View {
        ZStack {
            // 1. 专注弧（上半圈，深海蔚蓝到极光紫，象征深度沉浸）
            ArcShape(startAngle: .degrees(38), endAngle: .degrees(192))
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.52, blue: 1.0), // Apple Focus Blue #0A84FF
                            Color(red: 0.38, green: 0.35, blue: 0.95)  // Apple Indigo #5E5CE6
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: max(1.5, size * 0.16), lineCap: .round)
                )
            
            // 2. 休息弧（下半圈，苹果薄荷绿到晨曦青，象征呼吸与身心复原）
            ArcShape(startAngle: .degrees(218), endAngle: .degrees(372))
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.82, blue: 0.38), // Apple Mint Green #30D158
                            Color(red: 0.22, green: 0.84, blue: 0.68)  // Mint Cyan
                        ],
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    ),
                    style: StrokeStyle(lineWidth: max(1.5, size * 0.16), lineCap: .round)
                )
        }
        .frame(width: size, height: size)
        .shadow(color: showGlow ? Color(red: 0.05, green: 0.52, blue: 1.0).opacity(0.38) : Color.clear, radius: size * 0.18)
    }
}

/// 基础圆弧绘制形状
private struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let strokeInset = rect.width * 0.09
        let radius = max(1.0, min(rect.width, rect.height) / 2.0 - strokeInset)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
