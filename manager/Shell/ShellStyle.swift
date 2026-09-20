import SwiftUI

enum ChidiStyle {
    static let purple = Color.accentColor
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct ShellSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content
        }
    }
}

struct EmptyCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(ChidiStyle.purple)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(ChidiStyle.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct InkLandscape: View {
    var body: some View {
        Canvas { context, size in
            for layer in 0..<3 {
                let offset = CGFloat(layer) * 0.11
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: size.height * (0.60 + offset)))
                ridge.addCurve(
                    to: CGPoint(x: size.width * 0.58, y: size.height * (0.52 + offset)),
                    control1: CGPoint(x: size.width * 0.20, y: size.height * (0.28 + offset)),
                    control2: CGPoint(x: size.width * 0.32, y: size.height * (0.85 + offset))
                )
                ridge.addCurve(
                    to: CGPoint(x: size.width, y: size.height * (0.38 + offset)),
                    control1: CGPoint(x: size.width * 0.82, y: size.height * (0.08 + offset)),
                    control2: CGPoint(x: size.width * 0.88, y: size.height * (0.48 + offset))
                )
                ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                ridge.addLine(to: CGPoint(x: 0, y: size.height))
                ridge.closeSubpath()
                context.fill(ridge, with: .color(ChidiStyle.purple.opacity(0.06 + Double(layer) * 0.035)))
            }
        }
        .accessibilityHidden(true)
    }
}
