import ComposableArchitecture
import Foundation
import Testing
@testable import SkeenStatus

@MainActor
@Suite("Settings")
struct SettingsFeatureTests {

    private func makeStore(config: Config, keychain: Keychain) -> TestStoreOf<SettingsFeature> {
        var state = SettingsFeature.State()
        state.$config = Shared(value: config)
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.keychain = keychain
            $0.loginItem = LoginItem(isEnabled: { false }, setEnabled: { _ in })
        }
        store.exhaustivity = .off
        return store
    }

    @Test func savingKeepsThePasswordOutOfTheConfig() async {
        let keychain = Keychain.inMemory()
        let store = makeStore(config: .default, keychain: keychain)

        await store.send(.onAppear)
        await store.send(\.binding.password, "s3cret")
        await store.send(\.binding.clashSecret, "api")
        await store.send(.binding(.set(\.draft.intervalSeconds, 30)))
        #expect(store.state.hasChanges)

        await store.send(.saveTapped)
        await store.receive(\.delegate.saved)

        #expect(store.state.config.intervalSeconds == 30)
        #expect(keychain.read("admin") == "s3cret")
        #expect(keychain.read(Config.clashSecretAccount) == "api")
        #expect(store.state.hasChanges == false)
        let json = String(decoding: try! JSONEncoder().encode(store.state.config), as: UTF8.self)
        #expect(!json.contains("s3cret"))
    }

    @Test func pointingAtAnotherRouterForgetsThePinnedKey() async {
        var config = Config.default
        config.hostKey = "ssh-ed25519 AAAA"
        let store = makeStore(config: config, keychain: .inMemory())

        await store.send(.onAppear)
        await store.send(.binding(.set(\.draft.port, 22)))
        await store.send(.saveTapped)
        #expect(store.state.config.hostKey == "")
    }

    @Test func savingTheSameRouterKeepsAKeyPinnedMeanwhile() async {
        let store = makeStore(config: .default, keychain: .inMemory())
        await store.send(.onAppear)
        store.state.$config.withLock { $0.hostKey = "ssh-ed25519 BBBB" }
        await store.send(.binding(.set(\.draft.intervalSeconds, 20)))
        await store.send(.saveTapped)
        #expect(store.state.config.hostKey == "ssh-ed25519 BBBB")
    }

    @Test func resetOnlyTouchesTheDraft() async {
        var config = Config.default
        config.gateway = "10.0.0.1"
        let store = makeStore(config: config, keychain: .inMemory(["admin": "pw"]))
        await store.send(.onAppear)
        await store.send(.resetTapped)
        await store.send(\.alert.presented.confirmReset)
        #expect(store.state.draft.gateway == Config.default.gateway)
        #expect(store.state.password == "")
        #expect(store.state.config.gateway == "10.0.0.1")
    }
}
