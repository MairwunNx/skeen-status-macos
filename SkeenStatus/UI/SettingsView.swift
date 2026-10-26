import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    let engine: Engine

    @State private var draft: Config = .default
    @State private var password: String = ""
    @State private var testResult: TestResult?
    @State private var testing = false
    @State private var showResetConfirm = false

    @State private var version: SkeenVersion?
    @State private var loadingVersion = false
    @State private var runningControl: SkeenControl?
    @State private var controlResult: ControlResult?
    @State private var pendingControl: SkeenControl?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    private struct ControlResult {
        let control: SkeenControl
        let success: Bool
        let message: String
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    connectionSection
                    postConnectSection
                    statusSection
                    controlSection
                    logsSection
                    downScriptsSection
                    recoverScriptsSection
                    optionsSection
                }
                .padding(20)
            }
            footer
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear(perform: loadDraft)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(status: statusColor(for: appState.status)))
                    .frame(width: 16, height: 16)
                Text("Skeen Status")
                    .font(.largeTitle.bold())
                Spacer()
                Text("v\(appVersion)")
                    .foregroundStyle(.secondary)
            }
            Text("Мониторинг статуса skeen на роутере Keenetic и запуск сценариев при его падении/восстановлении.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Sections

    private var connectionSection: some View {
        SectionCard(title: "Подключение") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Шлюз роутера")
                    TextField("192.168.1.1", text: $draft.gateway)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.gateway")
                    Text("Порт")
                    TextField("2022", value: $draft.port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                GridRow {
                    Text("Логин")
                    TextField("admin", text: $draft.login)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(3)
                }
                GridRow {
                    Text("Пароль")
                    SecureField("••••••••", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(3)
                }
            }

            HStack(spacing: 12) {
                Button(testing ? "Проверка…" : "Проверить связь") {
                    runConnectionTest()
                }
                .disabled(testing)
                .glassButton(prominent: false, reduceTransparency: reduceTransparency)

                if let testResult {
                    switch testResult {
                    case .success(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var postConnectSection: some View {
        SectionCard(title: "Команды после подключения (до проверки статуса)") {
            StringListEditor(
                hint: "Выполняются последовательно в той же SSH-сессии на роутере.",
                items: $draft.postConnectCommands
            )
        }
    }

    private var statusSection: some View {
        SectionCard(title: "Проверка статуса (поллинг)") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Команда статуса")
                    TextField("skeen status", text: $draft.statusCommand)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text("Как понять, что работает")
                    Picker("", selection: $draft.statusDetection) {
                        Text("Автоматически").tag(StatusDetection.automatic)
                        Text("По своему правилу").tag(StatusDetection.rule)
                    }
                    .labelsHidden()
                    .gridCellColumns(2)
                }
                if draft.statusDetection == .rule {
                    GridRow {
                        Text("Признак «running»")
                        TextField("Status: running", text: $draft.runningRule.pattern)
                            .textFieldStyle(.roundedBorder)
                        Picker("", selection: $draft.runningRule.mode) {
                            Text("substring").tag(MatchMode.substring)
                            Text("regex").tag(MatchMode.regex)
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }
                GridRow {
                    Text("Интервал опроса")
                    HStack(spacing: 6) {
                        TextField("15", value: $draft.intervalSeconds, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("сек")
                        Stepper("", value: $draft.intervalSeconds, in: 3...3600)
                            .labelsHidden()
                    }
                    .gridCellColumns(2)
                }
            }
        }
    }

    private var controlSection: some View {
        SectionCard(title: "Управление skeen") {
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Команда skeen")
                        TextField("skeen", text: $draft.skeenCommand)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.skeenCommand")
                    }
                }

                versionRow

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(SkeenControl.allCases) { control in
                        controlRow(control)
                    }
                }

                if let controlResult {
                    controlResultView(controlResult)
                }
            }
        }
        .task { await loadVersion() }
        .confirmationDialog(
            pendingControl.map { "Выполнить «\($0.title.lowercased())»? Это кратковременно прервёт трафик." } ?? "",
            isPresented: Binding(get: { pendingControl != nil }, set: { if !$0 { pendingControl = nil } })
        ) {
            if let control = pendingControl {
                Button(control.title, role: .destructive) {
                    pendingControl = nil
                    run(control)
                }
            }
            Button("Отмена", role: .cancel) { pendingControl = nil }
        }
    }

    private var versionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(version?.summary ?? (loadingVersion ? "Загрузка версии…" : "Версия неизвестна"))
                    .font(.callout)
                if let env = version?.environment {
                    Text(env)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let rev = version?.revision {
                    Text("Revision: \(rev)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button {
                Task { await loadVersion() }
            } label: {
                if loadingVersion {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(loadingVersion)
            .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            .accessibilityIdentifier("settings.refreshVersion")
        }
    }

    private func controlRow(_ control: SkeenControl) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if control.isDisruptive {
                    pendingControl = control
                } else {
                    run(control)
                }
            } label: {
                HStack(spacing: 6) {
                    if runningControl == control {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: control.systemImage)
                    }
                    Text(control.title)
                }
                .frame(width: 140, alignment: .leading)
            }
            .disabled(runningControl != nil)
            .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            .accessibilityIdentifier("settings.control.\(control.rawValue)")

            Text(control.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func controlResultView(_ result: ControlResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                "«\(result.control.title)»: \(result.success ? "выполнено" : "ошибка")",
                systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundStyle(result.success ? .green : .red)
            .font(.callout)

            if !result.message.isEmpty {
                ScrollView {
                    Text(result.message)
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

    // MARK: Logs

    private var logsSection: some View {
        SectionCard(title: "Логи sing-box") {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Файл лога")
                        TextField("/opt/var/log/sing-box.log", text: $draft.logFilePath)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.logPath")
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Строк")
                        HStack(spacing: 6) {
                            TextField("50", value: $draft.logLineCount, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Stepper("", value: $draft.logLineCount, in: 10...500, step: 10)
                                .labelsHidden()
                            Text("Изменения вступают в силу после «Сохранить».")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .gridCellColumns(2)
                    }
                }

                logViewerHeader
                logViewer
            }
        }
        .task {
            while !Task.isCancelled {
                await engine.refreshLogs()
                let interval = max(3, appState.config.intervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private var logViewerHeader: some View {
        HStack(spacing: 8) {
            if let lastLogCheck = appState.lastLogCheck {
                Text("Обновлено: \(timeString(lastLogCheck))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if appState.logError != nil {
                Label("ошибка обновления", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(appState.logError ?? "")
            }
            Spacer()
            Button {
                Task { await engine.refreshLogs() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .glassButton(prominent: false, reduceTransparency: reduceTransparency)
            .accessibilityIdentifier("settings.refreshLogs")
        }
    }

    private var logViewer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if appState.logLines.isEmpty {
                        Text(appState.logError != nil ? "Не удалось получить логи" : "Загрузка логов…")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        ForEach(appState.logLines) { line in
                            logRow(line).id(line.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 220)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
            )
            .onChange(of: appState.logLines) { _, lines in
                guard let last = lines.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func logRow(_ line: LogLine) -> some View {
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

    private var downScriptsSection: some View {
        SectionCard(title: "Сценарии при ПАДЕНИИ skeen (running → stopped)") {
            StringListEditor(
                hint: "Выполняются локально на этом Mac (/bin/sh -c), по порядку; ошибка одной не прерывает остальные.",
                items: $draft.onDownScripts
            )
        }
    }

    private var recoverScriptsSection: some View {
        SectionCard(title: "Сценарии при ВОССТАНОВЛЕНИИ skeen (stopped → running)") {
            StringListEditor(
                hint: "Выполняются локально на этом Mac (/bin/sh -c), по порядку.",
                items: $draft.onRecoverScripts
            )
        }
    }

    private var optionsSection: some View {
        SectionCard(title: "Дополнительно") {
            Toggle("Считать недоступность роутера падением skeen", isOn: $draft.treatUnreachableAsDown)
            Toggle("Запускать при входе в систему", isOn: $draft.launchAtLogin)
            if appState.loginItemEnabled != draft.launchAtLogin {
                Text(appState.loginItemEnabled ? "Сейчас: включён" : "Сейчас: выключен")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(status: statusColor(for: appState.status)))
                        .frame(width: 10, height: 10)
                    Text(statusFooter(
                        state: appState.status,
                        lastCheck: appState.lastCheck,
                        gateway: appState.config.gateway
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Открыть лог") { openLog() }
                    .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                Button("Сбросить") { showResetConfirm = true }
                    .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                Button("Сохранить") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .glassButton(prominent: true, reduceTransparency: reduceTransparency)
                    .accessibilityIdentifier("settings.save")
            }
            .padding(16)
        }
        .confirmationDialog("Сбросить настройки к значениям по умолчанию?", isPresented: $showResetConfirm) {
            Button("Сбросить", role: .destructive) { resetToDefaults() }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Actions

    private func loadDraft() {
        draft = appState.config
        password = Keychain.readPassword(account: appState.config.login) ?? ""
    }

    private func save() {
        engine.applyConfig(draft, password: password)
    }

    private func resetToDefaults() {
        draft = .default
        password = ""
    }

    private func openLog() {
        NSWorkspace.shared.open(AppLog.shared.url)
    }

    private func runConnectionTest() {
        testing = true
        testResult = nil
        let config = draft
        let pwd = password
        Task {
            let result = await engine.testConnection(config, password: pwd)
            testing = false
            switch result {
            case .success(let message):
                testResult = .success(message)
            case .failure(let error):
                testResult = .failure("Ошибка: \(error.localizedDescription)")
            }
        }
    }

    private func loadVersion() async {
        guard !loadingVersion else { return }
        loadingVersion = true
        defer { loadingVersion = false }
        if case .success(let info) = await engine.fetchSkeenVersion(), !info.isEmpty {
            version = info
        }
    }

    private func run(_ control: SkeenControl) {
        runningControl = control
        controlResult = nil
        Task {
            let result = await engine.runSkeenControl(control)
            runningControl = nil
            switch result {
            case .success(let output):
                let text = cleanOutput(output)
                controlResult = ControlResult(control: control, success: true, message: text)
            case .failure(let error):
                controlResult = ControlResult(control: control, success: false, message: error.localizedDescription)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
