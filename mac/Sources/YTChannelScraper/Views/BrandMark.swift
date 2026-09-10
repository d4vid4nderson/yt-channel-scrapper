import SwiftUI

/// The red badge with a ringed download arrow — the same mark the web app used.
struct BrandMark: View {
    var width: CGFloat = 44

    private var height: CGFloat { width * 124 / 176 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.17, style: .continuous)
                .fill(Color(red: 1, green: 0, blue: 0))
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: width * 0.034)
                    .frame(width: width * 0.36, height: width * 0.36)
                DownArrow()
                    .stroke(.white, style: StrokeStyle(lineWidth: width * 0.034,
                                                       lineCap: .round, lineJoin: .round))
                    .frame(width: width * 0.16, height: width * 0.20)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private struct DownArrow: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let midX = rect.midX
            let stemTop = rect.minY
            let stemBottom = rect.maxY * 0.72
            path.move(to: CGPoint(x: midX, y: stemTop))
            path.addLine(to: CGPoint(x: midX, y: stemBottom))
            path.move(to: CGPoint(x: midX - rect.width * 0.42, y: stemBottom - rect.width * 0.42))
            path.addLine(to: CGPoint(x: midX, y: stemBottom))
            path.addLine(to: CGPoint(x: midX + rect.width * 0.42, y: stemBottom - rect.width * 0.42))
            path.move(to: CGPoint(x: midX - rect.width * 0.55, y: rect.maxY))
            path.addLine(to: CGPoint(x: midX + rect.width * 0.55, y: rect.maxY))
            return path
        }
    }
}
