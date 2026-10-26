import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// SSH, status detection, polling, and the Clash API.
struct ConnectionSettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SettingsPage(store: store) {
            SectionCard(title: "Router", systemImage: "wifi.router") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Address")
                        TextField("192.168.1.1", text: $store.draft.gateway)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.gateway")
                        Text("SSH Port")
                        TextField("2022", value: $store.draft.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    GridRow {
                        Text("Login")
                        TextField("admin", text: $store.draft.login)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(3)
                    }
                    GridRow {
                        Text("Password")
                        SecureField("Kept in the Keychain", text: $store.password)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(3)
                    }
                }

                HStack(spacing: 12) {
                    Button(store.test == .running ? String(localized: "Checking…") : String(localized: "Test Connection")) {
                        store.send(.testTapped)
                    }
                    .disabled(store.test == .running)
                    .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                    .accessibilityIdentifier("settings.test")

                    switch store.test {
                    case .succeeded(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    case .failed(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .lineLimit(2)
                    case .running, nil:
                        EmptyView()
                    }
                }

                hostKeyRow
            }

            SectionCard(title: "Commands After Login", systemImage: "terminal") {
                StringListEditor(
                    hint: "Run in order in the same SSH session, before the status check. Keenetic needs “exec sh” to get from its CLI to a shell.",
                    items: $store.draft.postConnectCommands
                )
            }

            SectionCard(title: "Status Check", systemImage: "waveform.path.ecg") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Command")
                        TextField("skeen status", text: $store.draft.statusCommand)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Text("skeen Command")
                        TextField("skeen", text: $store.draft.skeenCommand)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Text("How to Tell It Runs")
                        Picker("", selection: $store.draft.statusDetection) {
                            Text("Automatically").tag(StatusDetection.automatic)
                            Text("By My Own Rule").tag(StatusDetection.rule)
                        }
                        .labelsHidden()
                        .gridCellColumns(2)
                    }
                    if store.draft.statusDetection == .rule {
                        GridRow {
                            Text("“Running” Marker")
                            TextField("Status: running", text: $store.draft.runningRule.pattern)
                                .textFieldStyle(.roundedBorder)
                            Picker("", selection: $store.draft.runningRule.mode) {
                                Text("Substring").tag(MatchMode.substring)
                                Text("Regex").tag(MatchMode.regex)
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                    }
                    GridRow {
                        Text("Interval")
                        HStack(spacing: 6) {
                            TextField("15", value: $store.draft.intervalSeconds, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Stepper("", value: $store.draft.intervalSeconds, in: 3...3600)
                                .labelsHidden()
                            Text("seconds")
                        }
                        .gridCellColumns(2)
                    }
                }
                Text("Automatically: running when skeen shows a PID or the word “running”, in any language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionCard(title: "sing-box Clash API", systemImage: "point.3.connected.trianglepath.dotted") {
                Toggle("Ask sing-box Directly", isOn: $store.draft.clashAPIEnabled)
                if store.draft.clashAPIEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Address")
                            TextField("http://\(store.draft.gateway):9090", text: $store.draft.clashAPIURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Secret")
                            SecureField("Empty if not set", text: $store.clashSecret)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                Text("This is `experimental.clash_api` in the sing-box config. The overview takes traffic, connections, and the current outbound from it, and it shows sing-box is alive even when SSH drops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var hostKeyRow: some View {
        let key = store.config.hostKey
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: key.isBlank ? "lock.open" : "lock.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.isBlank ? String(localized: "The router’s key isn’t pinned yet") : String(localized: "The router’s key is pinned"))
                    .font(.callout)
                if !key.isBlank {
                    Text(key)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if !key.isBlank {
                Button("Forget Key") { store.send(.forgetHostKeyTapped) }
                    .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            }
        }
    }
}

/// Scripts that run on this Mac when skeen goes down or comes back.
struct ScriptsSettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        SettingsPage(store: store) {
            SectionCard(title: "When skeen Stops", systemImage: "bolt.slash") {
                StringListEditor(
                    hint: "Run on this Mac through /bin/sh -c, in order. One failing command doesn’t stop the rest.",
                    items: $store.draft.onDownScripts
                )
            }
            SectionCard(title: "When skeen Runs Again", systemImage: "bolt") {
                StringListEditor(
                    hint: "Run on this Mac through /bin/sh -c, in order.",
                    items: $store.draft.onRecoverScripts
                )
            }
            SectionCard(title: "Unreachable Router", systemImage: "wifi.exclamationmark") {
                Toggle("Treat an unreachable router as stopped skeen", isOn: $store.draft.treatUnreachableAsDown)
                Text("Then losing the router also runs the “stops” scripts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Notifications, launch at login, and the app's own log.
struct GeneralSettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SettingsPage(store: store) {
            SectionCard(title: "Language", systemImage: "globe") {
                Picker("Language", selection: Binding(
                    get: { store.language },
                    set: { store.send(.languageChanged($0)) }
                )) {
                    Text("As in macOS").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Русский").tag(AppLanguage.russian)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("settings.language")
                if store.needsRelaunch {
                    HStack {
                        Text("The new language shows after a relaunch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch Now") { store.send(.relaunchTapped) }
                            .glassButton(prominent: true, reduceTransparency: reduceTransparency)
                    }
                } else {
                    Text("You can also pick it in System Settings → General → Language & Region → Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SectionCard(title: "Notifications", systemImage: "bell.badge") {
                Toggle("Tell me when skeen stops and runs again", isOn: $store.draft.notificationsEnabled)
                Toggle("Tell me when the router is unreachable", isOn: $store.draft.notifyUnreachable)
                    .disabled(!store.draft.notificationsEnabled)
                Text("One bad check is no reason to worry: the app checks again 3 seconds later and tells you only if it holds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SectionCard(title: "Startup", systemImage: "power") {
                Toggle("Open at login", isOn: $store.draft.launchAtLogin)
                if store.loginItemEnabled != store.draft.launchAtLogin {
                    Text(store.loginItemEnabled ? String(localized: "On right now") : String(localized: "Off right now"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SectionCard(title: "Move to Another Mac", systemImage: "arrow.left.arrow.right") {
                Text("A file with the settings, the SSH password, the Clash API secret, and the router’s key, sealed with your passphrase: AES-256-GCM under a PBKDF2-SHA256 key. Without the passphrase the file is useless, so send the passphrase separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export…") { store.send(.exportTapped) }
                        .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                        .accessibilityIdentifier("settings.export")
                    Button("Import…") { store.send(.importTapped) }
                        .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                        .accessibilityIdentifier("settings.import")
                    if let notice = store.transferNotice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                            .lineLimit(2)
                    }
                }
            }
            SectionCard(title: "Diagnostics", systemImage: "stethoscope") {
                HStack {
                    Text("The app’s own log: connections, state changes, scripts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Log") { store.send(.openAppLogTapped) }
                        .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                }
                HStack {
                    Text("Reset every setting to its default.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset…") { store.send(.resetTapped) }
                        .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                }
            }
        }
    }
}

/// Asks for the passphrase that seals or opens a settings file.
private struct PassphraseSheet: View {
    @Bindable var store: StoreOf<SettingsFeature>

    private var isExport: Bool { store.transfer == .export }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isExport ? String(localized: "Passphrase for the Settings File") : String(localized: "Passphrase of the Settings File"))
                .font(.title3.weight(.semibold))
            Text(isExport
                 ? String(localized: "Choose a passphrase of at least \(SettingsTransfer.minimumPassphraseLength) characters. You’ll need it on the other Mac, and nobody can recover it.")
                 : String(localized: "Enter the passphrase the file was sealed with. The settings from the file replace the current ones."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Passphrase", text: $store.passphrase)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.send(.transferConfirmed) }
            if isExport {
                SecureField("Once more", text: $store.passphraseConfirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.send(.transferConfirmed) }
            }
            if let error = store.transferError {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                if store.isTransferring {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { store.send(.transferCancelled) }
                    .keyboardShortcut(.cancelAction)
                Button(isExport ? String(localized: "Encrypt") : String(localized: "Decrypt")) { store.send(.transferConfirmed) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(store.passphrase.isEmpty || store.isTransferring)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

/// The sealed bytes, handed to the save panel as they are.
private struct SettingsFile: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A scrolling settings page with the save bar pinned under it.
private struct SettingsPage<Content: View>: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(20)
            }
            if store.hasChanges || store.saveError != nil {
                saveBar
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .sheet(isPresented: Binding(
            get: { store.transfer != nil },
            set: { if !$0 { store.send(.transferCancelled) } }
        )) {
            PassphraseSheet(store: store)
        }
        .fileExporter(
            isPresented: Binding(get: { store.exportData != nil }, set: { if !$0 { store.send(.exportSaved(.failure(CancellationError()))) } }),
            document: store.exportData.map(SettingsFile.init(data:)),
            contentType: .data,
            defaultFilename: "Skeen Status.skeensettings"
        ) { result in
            store.send(.exportSaved(result))
        }
        .fileImporter(
            isPresented: Binding(get: { store.isPickingImport }, set: { if !$0 && store.isPickingImport { store.send(.importPicked(.failure(CancellationError()))) } }),
            allowedContentTypes: [.data]
        ) { result in
            store.send(.importPicked(result))
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let error = store.saveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else {
                    Text("There are unsaved changes")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button("Revert") { store.send(.revertTapped) }
                    .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                Button("Save") { store.send(.saveTapped) }
                    .keyboardShortcut("s", modifiers: .command)
                    .glassButton(prominent: true, reduceTransparency: reduceTransparency)
                    .accessibilityIdentifier("settings.save")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
