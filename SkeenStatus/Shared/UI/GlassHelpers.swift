import SwiftUI

/// Section container with a Liquid Glass background, falling back to a solid
/// material when Reduce Transparency is enabled.
struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            } else {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
    }
}

private struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    /// Native Liquid Glass behind a rounded card, or a solid fill under
    /// Reduce Transparency.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

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
