import SwiftUI

extension Color {
    init(status: StatusColor) {
        switch status {
        case .green: self = .green
        case .red: self = .red
        case .yellow: self = .yellow
        case .gray: self = .gray
        }
    }

    /// Base tint for a log level. Applied at low opacity in the viewer so the
    /// rows stay legible on both light and dark themes.
    init(logLevel: LogLevel) {
        switch logLevel {
        case .error, .fatal, .panic: self = .red
        case .warn: self = .orange
        case .info: self = .green
        case .debug, .trace: self = .purple
        case .other: self = .secondary
        }
    }
}

/// Section container with a Liquid Glass background, falling back to a solid
/// material when Reduce Transparency is enabled.
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(GlassPanel(reduceTransparency: reduceTransparency))
    }
}

private struct GlassPanel: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        } else {
            content.glassEffect(in: .rect(cornerRadius: 16))
        }
    }
}

extension View {
    /// Applies a glass button style, or a standard bordered style under
    /// Reduce Transparency.
    @ViewBuilder
    func glassButton(prominent: Bool, reduceTransparency: Bool) -> some View {
        if reduceTransparency {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        } else {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        }
    }
}
