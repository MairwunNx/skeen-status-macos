import ComposableArchitecture
import Foundation
import Testing
@testable import SkeenStatus

@MainActor
@Suite("Service control")
struct ServiceControlFeatureTests {

    private func makeStore(commands: LockIsolated<[String]>) -> TestStoreOf<ServiceControlFeature> {
        var state = ServiceControlFeature.State()
        state.$config = Shared(value: .default)
        state.$snapshot = Shared(value: SkeenSnapshot())
        let store = TestStore(initialState: state) {
            ServiceControlFeature()
        } withDependencies: {
            $0.skeen.control = { skeen, control in
                commands.withValue { $0.append("\(skeen) \(control.rawValue)") }
                return "\u{1B}[32mok\u{1B}[0m\r\n"
            }
        }
        store.exhaustivity = .off
        return store
    }

    @Test func startRunsAtOnceAndAsksForACheck() async {
        let commands = LockIsolated<[String]>([])
        let store = makeStore(commands: commands)

        await store.send(.controlTapped(.start))
        await store.receive(\.run)
        await store.receive(\.finished)
        await store.receive(\.delegate.serviceChanged)

        #expect(commands.value == ["skeen start"])
        #expect(store.state.outcome == .init(control: .start, succeeded: true, output: "ok"))
        #expect(store.state.running == nil)
    }

    @Test func stopWaitsForConfirmation() async {
        let commands = LockIsolated<[String]>([])
        let store = makeStore(commands: commands)

        await store.send(.controlTapped(.stop))
        #expect(store.state.confirmation != nil)
        #expect(commands.value.isEmpty)

        await store.send(\.confirmation.presented.run, .stop)
        await store.receive(\.finished)
        #expect(commands.value == ["skeen stop"])
    }

    @Test func checkDoesNotAskForAStatusCheck() async {
        let commands = LockIsolated<[String]>([])
        let store = makeStore(commands: commands)
        store.exhaustivity = .on

        await store.send(.controlTapped(.check))
        await store.receive(\.run) { $0.running = .check }
        await store.receive(\.finished) {
            $0.running = nil
            $0.outcome = .init(control: .check, succeeded: true, output: "ok")
        }
    }
}
