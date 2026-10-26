import ComposableArchitecture
import SwiftUI

/// SSH, status detection, polling, and the Clash API.
struct ConnectionSettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SettingsPage(store: store) {
            SectionCard(title: "Роутер", systemImage: "wifi.router") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Адрес")
                        TextField("192.168.1.1", text: $store.draft.gateway)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings.gateway")
                        Text("Порт SSH")
                        TextField("2022", value: $store.draft.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    GridRow {
                        Text("Логин")
                        TextField("admin", text: $store.draft.login)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(3)
                    }
                    GridRow {
                        Text("Пароль")
                        SecureField("Хранится в Связке ключей", text: $store.password)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(3)
                    }
                }

                HStack(spacing: 12) {
                    Button(store.test == .running ? "Проверяю…" : "Проверить связь") {
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

            SectionCard(title: "Команды после входа", systemImage: "terminal") {
                StringListEditor(
                    hint: "Выполняются по порядку в той же SSH-сессии, до проверки статуса. На Keenetic нужна «exec sh», чтобы попасть из CLI в оболочку.",
                    items: $store.draft.postConnectCommands
                )
            }

            SectionCard(title: "Проверка статуса", systemImage: "waveform.path.ecg") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Команда")
                        TextField("skeen status", text: $store.draft.statusCommand)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Команда skeen")
                        TextField("skeen", text: $store.draft.skeenCommand)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Как понять, что работает")
                        Picker("", selection: $store.draft.statusDetection) {
                            Text("Автоматически").tag(StatusDetection.automatic)
                            Text("По своему правилу").tag(StatusDetection.rule)
                        }
                        .labelsHidden()
                        .gridCellColumns(2)
                    }
                    if store.draft.statusDetection == .rule {
                        GridRow {
                            Text("Признак «работает»")
                            TextField("Status: running", text: $store.draft.runningRule.pattern)
                                .textFieldStyle(.roundedBorder)
                            Picker("", selection: $store.draft.runningRule.mode) {
                                Text("Подстрока").tag(MatchMode.substring)
                                Text("Regex").tag(MatchMode.regex)
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                    }
                    GridRow {
                        Text("Интервал")
                        HStack(spacing: 6) {
                            TextField("15", value: $store.draft.intervalSeconds, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Stepper("", value: $store.draft.intervalSeconds, in: 3...3600)
                                .labelsHidden()
                            Text("секунд")
                        }
                        .gridCellColumns(2)
                    }
                }
                Text("Автоматически: работает, если skeen показал PID или слово «running», на любом языке.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionCard(title: "Clash API sing-box", systemImage: "point.3.connected.trianglepath.dotted") {
                Toggle("Спрашивать sing-box напрямую", isOn: $store.draft.clashAPIEnabled)
                if store.draft.clashAPIEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Адрес")
                            TextField("http://\(store.draft.gateway):9090", text: $store.draft.clashAPIURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Секрет")
                            SecureField("Пусто, если не задан", text: $store.clashSecret)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                Text("Это `experimental.clash_api` из конфига sing-box. Отсюда берутся трафик, соединения и текущий выход на «Обзоре», и по нему видно, что sing-box жив, даже если SSH отвалился.")
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
                Text(key.isBlank ? "Ключ роутера ещё не закреплён" : "Ключ роутера закреплён")
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
                Button("Забыть ключ") { store.send(.forgetHostKeyTapped) }
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
            SectionCard(title: "Когда skeen остановился", systemImage: "bolt.slash") {
                StringListEditor(
                    hint: "Выполняются на этом Mac через /bin/sh -c, по порядку. Ошибка одной команды не останавливает остальные.",
                    items: $store.draft.onDownScripts
                )
            }
            SectionCard(title: "Когда skeen снова работает", systemImage: "bolt") {
                StringListEditor(
                    hint: "Выполняются на этом Mac через /bin/sh -c, по порядку.",
                    items: $store.draft.onRecoverScripts
                )
            }
            SectionCard(title: "Недоступный роутер", systemImage: "wifi.exclamationmark") {
                Toggle("Считать недоступный роутер остановленным skeen", isOn: $store.draft.treatUnreachableAsDown)
                Text("Тогда потеря связи с роутером тоже запустит сценарии «остановился».")
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
            SectionCard(title: "Уведомления", systemImage: "bell.badge") {
                Toggle("Сообщать, когда skeen останавливается и снова работает", isOn: $store.draft.notificationsEnabled)
                Toggle("Сообщать, когда роутер недоступен", isOn: $store.draft.notifyUnreachable)
                    .disabled(!store.draft.notificationsEnabled)
                Text("Одна плохая проверка ещё не повод: приложение перепроверяет через 3 секунды и сообщает, только если всё подтвердилось.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SectionCard(title: "Запуск", systemImage: "power") {
                Toggle("Открывать при входе в систему", isOn: $store.draft.launchAtLogin)
                if store.loginItemEnabled != store.draft.launchAtLogin {
                    Text(store.loginItemEnabled ? "Сейчас включено" : "Сейчас выключено")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SectionCard(title: "Диагностика", systemImage: "stethoscope") {
                HStack {
                    Text("Журнал приложения: подключения, смены состояния, сценарии.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Открыть журнал") { store.send(.openAppLogTapped) }
                        .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                }
                HStack {
                    Text("Вернуть все настройки по умолчанию.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Сбросить…") { store.send(.resetTapped) }
                        .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                }
            }
        }
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
                    Text("Есть несохранённые изменения")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button("Отменить") { store.send(.revertTapped) }
                    .glassButton(prominent: false, reduceTransparency: reduceTransparency)
                Button("Сохранить") { store.send(.saveTapped) }
                    .keyboardShortcut("s", modifiers: .command)
                    .glassButton(prominent: true, reduceTransparency: reduceTransparency)
                    .accessibilityIdentifier("settings.save")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
