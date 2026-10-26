import ComposableArchitecture
import Foundation

/// Edits a draft of the config and applies it on «Сохранить».
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.config) var config
        var draft: Config = .default
        var password = ""
        var clashSecret = ""
        var savedPassword = ""
        var savedClashSecret = ""
        var test: TestStatus?
        var loginItemEnabled = false
        var saveError: String?
        @Presents var alert: AlertState<Action.Alert>?

        var hasChanges: Bool {
            var current = config
            current.hostKey = draft.hostKey
            return draft != current || password != savedPassword || clashSecret != savedClashSecret
        }
    }

    enum TestStatus: Equatable {
        case running
        case succeeded(String)
        case failed(String)
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case saveTapped
        case revertTapped
        case resetTapped
        case testTapped
        case testFinished(Result<String, Error>)
        case forgetHostKeyTapped
        case openAppLogTapped
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        @CasePathable
        enum Alert: Equatable {
            case confirmReset
            case confirmForgetHostKey
        }

        @CasePathable
        enum Delegate: Equatable {
            case saved
        }
    }

    @Dependency(\.appLog) var appLog
    @Dependency(\.keychain) var keychain
    @Dependency(\.loginItem) var loginItem
    @Dependency(\.openURL) var openURL
    @Dependency(\.routerShell) var routerShell

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear, .revertTapped:
                state.draft = state.config
                state.savedPassword = keychain.read(state.config.login) ?? ""
                state.savedClashSecret = keychain.read(Config.clashSecretAccount) ?? ""
                state.password = state.savedPassword
                state.clashSecret = state.savedClashSecret
                state.loginItemEnabled = loginItem.isEnabled()
                state.saveError = nil
                return .none

            case .saveTapped:
                let oldLogin = state.config.login
                var config = state.draft
                let sameRouter = config.gateway == state.config.gateway && config.port == state.config.port
                config.hostKey = sameRouter ? state.config.hostKey : ""
                state.$config.withLock { $0 = config }
                state.draft = config

                if config.login != oldLogin || state.password != state.savedPassword {
                    keychain.save(state.password, config.login)
                }
                keychain.save(state.clashSecret, Config.clashSecretAccount)
                state.savedPassword = state.password
                state.savedClashSecret = state.clashSecret

                do {
                    try loginItem.setEnabled(config.launchAtLogin)
                    state.saveError = nil
                } catch {
                    appLog.write("login item error: \(error)")
                    state.saveError = "Не удалось изменить автозапуск: \(error.localizedDescription)"
                }
                state.loginItemEnabled = loginItem.isEnabled()
                appLog.write("settings saved")
                return .send(.delegate(.saved))

            case .resetTapped:
                state.alert = AlertState {
                    TextState("Вернуть настройки по умолчанию?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmReset) { TextState("Сбросить") }
                    ButtonState(role: .cancel) { TextState("Отмена") }
                } message: {
                    TextState("Изменения попадут в черновик. Чтобы применить их, нажмите «Сохранить».")
                }
                return .none

            case .alert(.presented(.confirmReset)):
                state.draft = .default
                state.password = ""
                state.clashSecret = ""
                return .none

            case .testTapped:
                state.test = .running
                var connection = state.draft.sshConnection(password: state.password)
                let sameRouter = state.draft.gateway == state.config.gateway && state.draft.port == state.config.port
                connection.trustedHostKey = sameRouter && !state.config.hostKey.isBlank ? state.config.hostKey : nil
                return .run { [connection] send in
                    await send(.testFinished(attempt { try await routerShell.test(connection) }))
                }

            case .testFinished(.success):
                state.test = .succeeded("Роутер \(state.draft.gateway):\(state.draft.port) принял логин и пароль")
                return .none

            case .testFinished(.failure(let error)):
                state.test = .failed(error.localizedDescription)
                return .none

            case .forgetHostKeyTapped:
                state.alert = AlertState {
                    TextState("Забыть ключ роутера?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmForgetHostKey) { TextState("Забыть") }
                    ButtonState(role: .cancel) { TextState("Отмена") }
                } message: {
                    TextState("При следующем подключении приложение доверится ключу, который покажет роутер. Делайте так, только если сменили роутер или прошивку.")
                }
                return .none

            case .alert(.presented(.confirmForgetHostKey)):
                state.$config.withLock { $0.hostKey = "" }
                state.draft.hostKey = ""
                appLog.write("forgot router host key")
                return .send(.delegate(.saved))

            case .openAppLogTapped:
                let url = appLog.url()
                return .run { _ in await openURL(url) }

            case .alert, .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}
