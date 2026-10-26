import ComposableArchitecture
import Foundation

/// Starts, stops, restarts, reloads, and checks skeen, and shows its version.
@Reducer
struct ServiceControlFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.config) var config
        @Shared(.skeenSnapshot) var snapshot
        var running: SkeenControl?
        var outcome: Outcome?
        var isLoadingVersion = false
        @Presents var confirmation: ConfirmationDialogState<Action.Confirmation>?
    }

    struct Outcome: Equatable {
        var control: SkeenControl
        var succeeded: Bool
        var output: String
    }

    enum Action {
        case controlTapped(SkeenControl)
        case run(SkeenControl)
        case finished(SkeenControl, Result<String, Error>)
        case refreshVersion
        case versionLoaded(Result<SkeenVersion, Error>)
        case confirmation(PresentationAction<Confirmation>)
        case delegate(Delegate)

        @CasePathable
        enum Confirmation: Equatable {
            case run(SkeenControl)
        }

        @CasePathable
        enum Delegate: Equatable {
            /// skeen may have changed state; check it now.
            case serviceChanged
        }
    }

    @Dependency(\.appLog) var appLog
    @Dependency(\.skeen) var skeen

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .controlTapped(let control):
                guard control.isDisruptive else { return .send(.run(control)) }
                state.confirmation = ConfirmationDialogState {
                    TextState("\(control.title) skeen?")
                } actions: {
                    ButtonState(role: .destructive, action: .run(control)) { TextState(control.title) }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                } message: {
                    TextState("Traffic through the proxy will stop for a moment.")
                }
                return .none

            case .confirmation(.presented(.run(let control))), .run(let control):
                guard state.running == nil else { return .none }
                state.running = control
                state.outcome = nil
                let command = state.config.skeenCommand
                return .run { send in
                    await send(.finished(control, attempt { try await skeen.control(command, control) }))
                }

            case .finished(let control, let result):
                state.running = nil
                switch result {
                case .success(let output):
                    appLog.write("skeen \(control.rawValue) -> \(cleanOutput(output).prefix(200))")
                    state.outcome = Outcome(control: control, succeeded: true, output: cleanOutput(output))
                case .failure(let error):
                    appLog.write("skeen \(control.rawValue) failed: \(error)")
                    state.outcome = Outcome(control: control, succeeded: false, output: error.localizedDescription)
                }
                return control.changesState ? .send(.delegate(.serviceChanged)) : .none

            case .refreshVersion:
                guard !state.isLoadingVersion else { return .none }
                state.isLoadingVersion = true
                let command = state.config.skeenCommand
                return .run { send in
                    await send(.versionLoaded(attempt { try await skeen.version(command) }))
                }

            case .versionLoaded(let result):
                state.isLoadingVersion = false
                if case .success(let version) = result, !version.isEmpty {
                    state.$snapshot.withLock { $0.version = version }
                }
                return .none

            case .confirmation, .delegate:
                return .none
            }
        }
        .ifLet(\.$confirmation, action: \.confirmation)
    }
}
