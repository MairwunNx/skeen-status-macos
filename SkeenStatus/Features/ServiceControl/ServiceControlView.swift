import ComposableArchitecture
import SwiftUI

struct ServiceControlView: View {
    @Bindable var store: StoreOf<ServiceControlFeature>
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SectionCard(title: "skeen Control", systemImage: "switch.2") {
            versionRow
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(SkeenControl.allCases) { control in
                    controlRow(control)
                }
            }
            if let outcome = store.outcome {
                outcomeView(outcome)
            }
        }
        .confirmationDialog($store.scope(state: \.confirmation, action: \.confirmation))
        .task { if store.snapshot.version == nil { store.send(.refreshVersion) } }
    }

    private var versionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                let version = store.snapshot.version
                Text(version?.summary ?? (store.isLoadingVersion ? String(localized: "Getting the version…") : String(localized: "Version unknown")))
                    .font(.callout)
                if let environment = version?.environment {
                    Text(environment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                store.send(.refreshVersion)
            } label: {
                if store.isLoadingVersion {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(store.isLoadingVersion)
            .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            .help("Refresh the version")
            .accessibilityIdentifier("service.refreshVersion")
        }
    }

    private func controlRow(_ control: SkeenControl) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                store.send(.controlTapped(control))
            } label: {
                HStack(spacing: 6) {
                    if store.running == control {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: control.systemImage)
                    }
                    Text(control.title)
                }
                .frame(width: 150, alignment: .leading)
            }
            .disabled(store.running != nil)
            .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            .accessibilityIdentifier("service.\(control.rawValue)")

            Text(control.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func outcomeView(_ outcome: ServiceControlFeature.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                outcome.succeeded ? String(localized: "“\(outcome.control.title)”: done") : String(localized: "“\(outcome.control.title)”: failed"),
                systemImage: outcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundStyle(outcome.succeeded ? .green : .red)
            .font(.callout)

            if !outcome.output.isEmpty {
                ScrollView {
                    Text(outcome.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                )
            }
        }
        .padding(.top, 4)
    }
}
