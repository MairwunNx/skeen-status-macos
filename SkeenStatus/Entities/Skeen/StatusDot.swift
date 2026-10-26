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

/// A status dot that glows while skeen runs.
struct StatusDot: View {
    let color: StatusColor
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(Color(status: color).gradient)
            .frame(width: size, height: size)
            .shadow(color: Color(status: color).opacity(color == .green ? 0.6 : 0), radius: size / 2)
    }
}
