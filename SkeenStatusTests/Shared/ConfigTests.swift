import Testing
import Foundation
@testable import SkeenStatus

@Suite("Config")
struct ConfigTests {

    @Test func defaultsMatchSpec() {
        let config = Config.default
        #expect(config.gateway == "192.168.1.1")
        #expect(config.port == 2022)
        #expect(config.statusCommand == "skeen status")
        #expect(config.statusDetection == .automatic)
        #expect(config.runningRule == RunningRule(pattern: "Status: running", mode: .substring))
        #expect(config.intervalSeconds == 15)
        #expect(config.postConnectCommands == ["exec sh"])
    }

    @Test func decodingEmptyObjectYieldsDefaults() throws {
        let data = Data("{}".utf8)
        let config = try JSONDecoder().decode(Config.self, from: data)
        #expect(config == .default)
    }

    @Test func decodingPartialOverridesOnlyGivenKeys() throws {
        let json = #"{"gateway":"10.0.0.1","intervalSeconds":30}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.gateway == "10.0.0.1")
        #expect(config.intervalSeconds == 30)
        #expect(config.port == Config.default.port)
        #expect(config.statusCommand == Config.default.statusCommand)
    }

    @Test func olderConfigWithoutDetectionDetectsAutomatically() throws {
        let json = #"{"runningRule":{"pattern":"запущен","mode":"substring"}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.statusDetection == .automatic)
        #expect(config.runningRule.pattern == "запущен")
    }

    @Test func encodeDecodeRoundTrips() throws {
        var config = Config.default
        config.gateway = "172.16.0.1"
        config.onDownScripts = ["logger down", "skeen start"]
        config.treatUnreachableAsDown = true

        let data = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(Config.self, from: data)
        #expect(restored == config)
    }

    @Test func sshConnectionDropsBlankPostConnectCommandsAndCarriesPassword() {
        var config = Config.default
        config.postConnectCommands = ["exec sh", "   ", "", "opkg update"]
        let connection = config.sshConnection(password: "secret")
        #expect(connection.postConnectCommands == ["exec sh", "opkg update"])
        #expect(connection.password == "secret")
        #expect(connection.host == config.gateway)
        #expect(connection.port == config.port)
        #expect(connection.username == config.login)
        #expect(connection.trustedHostKey == nil)
    }

    @Test func pinnedHostKeyGoesToTheSession() {
        var config = Config.default
        config.hostKey = "ssh-ed25519 AAAA"
        #expect(config.sshConnection(password: "").trustedHostKey == "ssh-ed25519 AAAA")
    }

    @Test func newFieldsDefaultWhenMissing() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"gateway":"10.0.0.1"}"#.utf8))
        #expect(config.hostKey == "")
        #expect(config.clashAPIEnabled)
        #expect(config.clashAPIURL == "")
        #expect(config.notificationsEnabled)
        #expect(config.notifyUnreachable)
    }

    @Test func pollIntervalIsClampedToThreeSeconds() {
        var config = Config.default
        config.intervalSeconds = 1
        #expect(config.pollInterval == .seconds(3))
    }
}
