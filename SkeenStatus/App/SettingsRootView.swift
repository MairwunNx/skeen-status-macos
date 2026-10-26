import ComposableArchitecture
import SwiftUI

/// The settings window: a sidebar of tabs, each one built from a feature.
struct SettingsRootView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(
                get: { store.tab },
                set: { if let tab = $0 { store.send(.selectTab(tab)) } }
            )) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            detail
                .navigationTitle(store.tab.title)
        }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear { store.send(.settings(.onAppear)) }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.tab {
        case .overview:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DashboardView(store: store.scope(state: \.monitor, action: \.monitor)) {
                        Button {
                            store.send(.monitor(.checkNow))
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.monitor.isChecking)
                        .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                        .help("Check Now")
                        .accessibilityIdentifier("overview.checkNow")
                    }
                    ServiceControlView(store: store.scope(state: \.service, action: \.service))
                }
                .padding(20)
            }
        case .logs:
            LogsView(store: store.scope(state: \.logs, action: \.logs))
        case .connection:
            ConnectionSettingsView(store: store.scope(state: \.settings, action: \.settings))
        case .scripts:
            ScriptsSettingsView(store: store.scope(state: \.settings, action: \.settings))
        case .general:
            GeneralSettingsView(store: store.scope(state: \.settings, action: \.settings))
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            StatusDot(color: statusColor(for: store.monitor.snapshot.state), size: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text("skeen \(store.monitor.snapshot.state.title)")
                    .font(.callout)
                Text("Skeen Status \(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
