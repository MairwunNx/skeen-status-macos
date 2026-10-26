import SwiftUI

/// Ordered, editable list of command strings with add/remove controls.
struct StringListEditor: View {
    let hint: LocalizedStringKey?
    @Binding var items: [String]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                    TextField("command", text: binding(for: index))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                }
            }

            HStack {
                Spacer()
                Button {
                    items.append("")
                } label: {
                    Image(systemName: "plus")
                }
                .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            }
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < items.count ? items[index] : "" },
            set: { if index < items.count { items[index] = $0 } }
        )
    }
}
