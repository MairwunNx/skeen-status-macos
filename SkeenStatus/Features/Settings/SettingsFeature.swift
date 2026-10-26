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
        var language: AppLanguage = .system
        /// The language on screen right now, and what the choice would show.
        var activeLanguage = "en"
        var systemLanguage = "en"
        var saveError: String?
        /// The passphrase sheet for moving settings to another Mac.
        var transfer: TransferMode?
        var passphrase = ""
        var passphraseConfirmation = ""
        var transferError: String?
        var isTransferring = false
        var transferNotice: String?
        /// A sealed file waiting for the save panel.
        var exportData: Data?
        var isPickingImport = false
        @Presents var alert: AlertState<Action.Alert>?

        /// A new language shows only after a relaunch.
        var needsRelaunch: Bool {
            language.resolved(systemPreferred: systemLanguage) != activeLanguage
        }

        var hasChanges: Bool {
            var current = config
            current.hostKey = draft.hostKey
            return draft != current || password != savedPassword || clashSecret != savedClashSecret
        }
    }

    enum TransferMode: Equatable {
        case export
        /// The picked file, waiting for its passphrase.
        case `import`(Data)
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
        case languageChanged(AppLanguage)
        case relaunchTapped
        case exportTapped
        case importTapped
        case importPicked(Result<URL, Error>)
        case transferConfirmed
        case transferCancelled
        case sealed(Result<Data, Error>)
        case opened(Result<SettingsBundle, Error>)
        case exportSaved(Result<URL, Error>)
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
    @Dependency(\.date.now) var now
    @Dependency(\.keychain) var keychain
    @Dependency(\.language) var language
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
                state.language = language.choice()
                state.activeLanguage = language.active()
                state.systemLanguage = language.systemPreferred()
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
                    state.saveError = String(localized: "Can’t change launch at login: \(error.localizedDescription)")
                }
                state.loginItemEnabled = loginItem.isEnabled()
                appLog.write("settings saved")
                return .send(.delegate(.saved))

            case .resetTapped:
                state.alert = AlertState {
                    TextState("Reset settings to defaults?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmReset) { TextState("Reset") }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                } message: {
                    TextState("The change goes into the draft. Press “Save” to apply it.")
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
                state.test = .succeeded(String(localized: "\(state.draft.gateway):\(state.draft.port) accepted the login and password"))
                return .none

            case .testFinished(.failure(let error)):
                state.test = .failed(error.localizedDescription)
                return .none

            case .forgetHostKeyTapped:
                state.alert = AlertState {
                    TextState("Forget the router’s key?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmForgetHostKey) { TextState("Forget") }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                } message: {
                    TextState("On the next connection the app trusts whatever key the router shows. Do this only after replacing the router or its firmware.")
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

            case .languageChanged(let choice):
                state.language = choice
                language.setChoice(choice)
                appLog.write("language set to \(choice.rawValue)")
                return .none

            case .relaunchTapped:
                return .run { _ in language.relaunch() }

            case .exportTapped:
                state.transfer = .export
                state.passphrase = ""
                state.passphraseConfirmation = ""
                state.transferError = nil
                state.transferNotice = nil
                return .none

            case .importTapped:
                state.transferNotice = nil
                state.isPickingImport = true
                return .none

            case .importPicked(.success(let url)):
                state.isPickingImport = false
                guard let data = try? Data(contentsOf: url) else {
                    state.transferNotice = String(localized: "Can’t read the file")
                    return .none
                }
                state.transfer = .import(data)
                state.passphrase = ""
                state.transferError = nil
                return .none

            case .importPicked(.failure):
                state.isPickingImport = false
                return .none

            case .transferConfirmed:
                guard let mode = state.transfer, !state.isTransferring else { return .none }
                let passphrase = state.passphrase
                switch mode {
                case .export:
                    guard passphrase.count >= SettingsTransfer.minimumPassphraseLength else {
                        state.transferError = SettingsTransferError.weakPassphrase.localizedDescription
                        return .none
                    }
                    guard passphrase == state.passphraseConfirmation else {
                        state.transferError = String(localized: "The passphrases don’t match")
                        return .none
                    }
                    state.isTransferring = true
                    let bundle = SettingsBundle(
                        config: state.config,
                        password: keychain.read(state.config.login) ?? "",
                        clashSecret: keychain.read(Config.clashSecretAccount) ?? "",
                        exportedAt: now
                    )
                    return .run { send in
                        await send(.sealed(attempt { try SettingsTransfer.seal(bundle, passphrase: passphrase) }))
                    }
                case .import(let data):
                    state.isTransferring = true
                    return .run { send in
                        await send(.opened(attempt { try SettingsTransfer.open(data, passphrase: passphrase) }))
                    }
                }

            case .transferCancelled:
                state.transfer = nil
                state.passphrase = ""
                state.passphraseConfirmation = ""
                state.isTransferring = false
                return .none

            case .sealed(let result):
                state.isTransferring = false
                switch result {
                case .success(let data):
                    state.transfer = nil
                    state.passphrase = ""
                    state.passphraseConfirmation = ""
                    state.exportData = data
                case .failure(let error):
                    state.transferError = error.localizedDescription
                }
                return .none

            case .opened(.success(let bundle)):
                state.isTransferring = false
                state.transfer = nil
                state.passphrase = ""
                state.$config.withLock { $0 = bundle.config }
                keychain.save(bundle.password, bundle.config.login)
                keychain.save(bundle.clashSecret, Config.clashSecretAccount)
                state.transferNotice = String(localized: "Settings moved in: router \(bundle.config.gateway)")
                appLog.write("settings imported for \(bundle.config.gateway)")
                return .merge(.send(.onAppear), .send(.delegate(.saved)))

            case .opened(.failure(let error)):
                state.isTransferring = false
                state.transferError = error.localizedDescription
                return .none

            case .exportSaved(let result):
                state.exportData = nil
                if case .success(let url) = result {
                    state.transferNotice = String(localized: "Saved to “\(url.lastPathComponent)”. Send the passphrase separately from the file.")
                    appLog.write("settings exported")
                }
                return .none

            case .alert, .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}
