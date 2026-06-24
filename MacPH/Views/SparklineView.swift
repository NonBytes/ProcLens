import SwiftUI

struct SparklineView: View {
    let values: [Double]
    var color: Color = .blue

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                let maxVal = max(values.max() ?? 1, 1)
                ZStack {
                    fillPath(in: geo.size, maxVal: maxVal)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
                    linePath(in: geo.size, maxVal: maxVal)
                        .stroke(color, lineWidth: 1)
                }
            }
        }
    }

    private func linePath(in size: CGSize, maxVal: Double) -> Path {
        Path { path in
            for (i, val) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat(min(val / maxVal, 1)))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }

    private func fillPath(in size: CGSize, maxVal: Double) -> Path {
        var p = linePath(in: size, maxVal: maxVal)
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }
}
