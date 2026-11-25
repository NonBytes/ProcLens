import SwiftUI

struct SparklineView: View {
    let values: [Double]
    var color: Color = .blue

    private let lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                let points = samplePoints(in: geo.size)
                ZStack {
                    areaPath(through: points, in: geo.size)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                    curvePath(through: points)
                        .stroke(
                            LinearGradient(
                                colors: [color.opacity(0.65), color],
                                startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func samplePoints(in size: CGSize) -> [CGPoint] {
        let maxVal = max(values.max() ?? 1, 1)
        let inset = lineWidth / 2
        let drawableHeight = max(size.height - lineWidth, 1)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(max(value / maxVal, 0), 1)
            return CGPoint(
                x: stepX * CGFloat(index),
                y: inset + drawableHeight * (1 - CGFloat(clamped))
            )
        }
    }

    private func curvePath(through points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            guard points.count > 2 else {
                for point in points.dropFirst() { path.addLine(to: point) }
                return
            }
            for index in 1..<points.count - 1 {
                let midpoint = CGPoint(
                    x: (points[index].x + points[index + 1].x) / 2,
                    y: (points[index].y + points[index + 1].y) / 2
                )
                path.addQuadCurve(to: midpoint, control: points[index])
            }
            if let last = points.last { path.addLine(to: last) }
        }
    }

    private func areaPath(through points: [CGPoint], in size: CGSize) -> Path {
        var path = curvePath(through: points)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
