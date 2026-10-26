import ComposableArchitecture
import SwiftUI

struct LogsView: View {
    @Bindable var store: StoreOf<LogsFeature>
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            viewer
            footer
        }
        .padding(20)
        .task { await store.send(.task).finish() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search", text: $store.search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Toggle("Warnings and errors only", isOn: $store.problemsOnly)
                .toggleStyle(.checkbox)
            Spacer()
            Toggle(isOn: $store.isPaused) {
                Image(systemName: store.isPaused ? "play.fill" : "pause.fill")
            }
            .toggleStyle(.button)
            .help(store.isPaused ? String(localized: "Resume") : String(localized: "Pause"))
            Button {
                store.send(.refresh)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            .help("Refresh")
            .accessibilityIdentifier("logs.refresh")
        }
    }

    private var viewer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let lines = store.visibleLines
                    if lines.isEmpty {
                        Text(placeholder)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        ForEach(lines) { line in
                            row(line).id(line.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
            )
            .onChange(of: store.lines) { _, lines in
                guard !store.isPaused, let last = lines.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var placeholder: String {
        if store.error != nil { return String(localized: "Can’t fetch the log") }
        if !store.lines.isEmpty { return String(localized: "Nothing found") }
        return String(localized: "Loading the log…")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Lines")
            TextField("50", value: Binding(
                get: { store.config.logLineCount },
                set: { store.send(.setLineCount($0)) }
            ), format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .frame(width: 60)
            Text(store.config.logFilePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let lastUpdate = store.lastUpdate {
                Text("Updated at \(timeString(lastUpdate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.time.isEmpty ? "—" : line.time)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(line.level.label)
                .foregroundStyle(Color(logLevel: line.level))
                .frame(width: 46, alignment: .leading)
            Text(line.message)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(Color(logLevel: line.level).opacity(line.level.isHighlighted ? 0.12 : 0))
    }
}

extension Color {
    /// Base tint for a log level, applied at low opacity so rows stay legible
    /// on both light and dark themes.
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
