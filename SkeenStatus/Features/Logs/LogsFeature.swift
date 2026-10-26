import ComposableArchitecture
import Foundation

/// Tails the sing-box log on the router while the logs tab is on screen.
@Reducer
struct LogsFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.config) var config
        var lines: [LogLine] = []
        var lastUpdate: Date?
        var error: String?
        var isPaused = false
        var problemsOnly = false
        var search = ""

        /// Lines left after the level filter and the search.
        var visibleLines: [LogLine] {
            lines.filter { line in
                (!problemsOnly || line.level.isHighlighted)
                    && (search.isBlank || line.message.localizedCaseInsensitiveContains(search))
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case refresh
        case loaded(Result<[LogLine], Error>)
        case setLineCount(Int)
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.skeen) var skeen

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                let interval = state.config.pollInterval
                return .run { send in
                    await send(.refresh)
                    for await _ in clock.timer(interval: interval) {
                        await send(.refresh)
                    }
                }

            case .refresh:
                guard !state.isPaused else { return .none }
                guard !state.config.logFilePath.isBlank else {
                    state.error = String(localized: "No log file path is set")
                    return .none
                }
                let command = state.config.logCommand
                return .run { send in
                    await send(.loaded(attempt { try await skeen.logs(command) }))
                }

            case .loaded(.success(let lines)):
                state.lines = lines
                state.lastUpdate = now
                state.error = nil
                return .none

            case .loaded(.failure(let error)):
                state.error = error.localizedDescription
                return .none

            case .setLineCount(let count):
                state.$config.withLock { $0.logLineCount = min(max(count, 10), 1000) }
                return .send(.refresh)
            }
        }
    }
}
