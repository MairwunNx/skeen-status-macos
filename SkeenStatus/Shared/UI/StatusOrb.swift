import SwiftUI

/// The colors and pace of one `StatusOrb` mood.
struct OrbPalette: Equatable {
    var base: Color
    var accent: Color
    var glow: Color
    /// 0 idles slowly, 1 ripples fast.
    var energy: Double
}

/// An animated orb drawn by the `statusOrb` Metal shader. It stands still
/// under Reduce Motion and while nobody can see it.
struct StatusOrb: View {
    let palette: OrbPalette
    var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 1.0 : context.date.timeIntervalSince(start)
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.statusOrb(
                    .float2(size, size),
                    .float(time),
                    .color(palette.base),
                    .color(palette.accent),
                    .float(palette.energy)
                ))
                .frame(width: size, height: size)
        }
        .shadow(color: palette.glow.opacity(0.55), radius: size / 3)
        .accessibilityHidden(true)
    }
}
