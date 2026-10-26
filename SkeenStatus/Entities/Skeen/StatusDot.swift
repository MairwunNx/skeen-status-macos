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
}

extension OrbPalette {
    /// Greens ripple while skeen runs, reds churn when it stopped, ambers
    /// pulse while the router is out of reach, and gray idles in between.
    init(status: StatusColor) {
        switch status {
        case .green:
            self.init(base: Color(red: 0.05, green: 0.55, blue: 0.30), accent: Color(red: 0.55, green: 1.0, blue: 0.62), glow: .green, energy: 0.55)
        case .red:
            self.init(base: Color(red: 0.55, green: 0.05, blue: 0.10), accent: Color(red: 1.0, green: 0.45, blue: 0.30), glow: .red, energy: 1.0)
        case .yellow:
            self.init(base: Color(red: 0.70, green: 0.42, blue: 0.0), accent: Color(red: 1.0, green: 0.88, blue: 0.35), glow: .yellow, energy: 0.8)
        case .gray:
            self.init(base: Color(white: 0.30), accent: Color(white: 0.75), glow: .clear, energy: 0.15)
        }
    }
}

/// The live status indicator: a shader orb in the colors of the state.
struct StatusDot: View {
    let color: StatusColor
    var size: CGFloat = 12

    var body: some View {
        StatusOrb(palette: OrbPalette(status: color), size: size)
            .animation(.easeInOut(duration: 0.4), value: color)
    }
}
