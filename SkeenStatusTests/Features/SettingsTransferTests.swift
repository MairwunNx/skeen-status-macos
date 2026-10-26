import CryptoKit
import Foundation
import Testing
@testable import SkeenStatus

@Suite("Encrypted settings file")
struct SettingsTransferTests {

    private var bundle: SettingsBundle {
        var config = Config.default
        config.gateway = "10.0.0.1"
        config.hostKey = "ssh-ed25519 AAAA"
        return SettingsBundle(config: config, password: "s3cret", clashSecret: "api", exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func roundTrips() throws {
        let data = try SettingsTransfer.seal(bundle, passphrase: "correct horse", iterations: 100_000)
        #expect(try SettingsTransfer.open(data, passphrase: "correct horse") == bundle)
    }

    @Test func keepsSecretsOutOfThePlainFile() throws {
        let data = try SettingsTransfer.seal(bundle, passphrase: "correct horse", iterations: 100_000)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("s3cret"))
        #expect(!text.contains("10.0.0.1"))
        #expect(text.contains("AES-256-GCM"))
    }

    @Test func eachFileGetsItsOwnSaltAndNonce() throws {
        let a = try JSONDecoder().decode(SettingsTransfer.Envelope.self, from: SettingsTransfer.seal(bundle, passphrase: "correct horse", iterations: 100_000))
        let b = try JSONDecoder().decode(SettingsTransfer.Envelope.self, from: SettingsTransfer.seal(bundle, passphrase: "correct horse", iterations: 100_000))
        #expect(a.kdf.salt != b.kdf.salt)
        #expect(a.cipher.nonce != b.cipher.nonce)
    }

    @Test func wrongPassphraseFails() throws {
        let data = try SettingsTransfer.seal(bundle, passphrase: "correct horse", iterations: 100_000)
        #expect(throws: SettingsTransferError.wrongPassphrase) { try SettingsTransfer.open(data, passphrase: "wrong horse") }
    }

    @Test func tamperedHeaderFails() throws {
        let data = try SettingsTransfer.seal(bundle, passphrase: "correct horse", iterations: 100_000)
        var envelope = try JSONDecoder().decode(SettingsTransfer.Envelope.self, from: data)
        envelope.kdf.iterations = 100_001
        let tampered = try JSONEncoder().encode(envelope)
        #expect(throws: SettingsTransferError.wrongPassphrase) { try SettingsTransfer.open(tampered, passphrase: "correct horse") }
    }

    @Test func shortPassphraseIsRefused() {
        #expect(throws: SettingsTransferError.weakPassphrase) { try SettingsTransfer.seal(bundle, passphrase: "1234567") }
    }

    @Test func foreignFileIsRecognized() {
        #expect(throws: SettingsTransferError.notASettingsFile) { try SettingsTransfer.open(Data("{}".utf8), passphrase: "whatever1") }
    }

    @Test func keyDerivationMatchesAKnownVector() {
        // PBKDF2-HMAC-SHA256("password", "salt", 1, 32 bytes), a published test vector.
        let key = SettingsTransfer.deriveKey(passphrase: "password", salt: Data("salt".utf8), iterations: 1)
        let hex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }
}
