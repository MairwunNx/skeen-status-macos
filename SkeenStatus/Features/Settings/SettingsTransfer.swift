import CommonCrypto
import CryptoKit
import Foundation

/// Everything another Mac needs to reach the same router.
struct SettingsBundle: Codable, Equatable, Sendable {
    var config: Config
    var password: String
    var clashSecret: String
    var exportedAt: Date
}

enum SettingsTransferError: Error, Equatable, LocalizedError {
    case weakPassphrase
    case notASettingsFile
    case unsupportedVersion(Int)
    case wrongPassphrase

    var errorDescription: String? {
        switch self {
        case .weakPassphrase: return "Код должен быть не короче \(SettingsTransfer.minimumPassphraseLength) символов"
        case .notASettingsFile: return "Это не файл настроек Skeen Status"
        case .unsupportedVersion(let version): return "Файл сделан версией формата \(version), эта версия приложения её не знает"
        case .wrongPassphrase: return "Неверный код, или файл повреждён"
        }
    }
}

/// The encrypted settings file.
///
/// The key comes from the user's passphrase through PBKDF2-HMAC-SHA256 with
/// 600 000 iterations and a random 16-byte salt (OWASP 2023). The bundle is
/// sealed with AES-256-GCM under a random 96-bit nonce. The header goes in as
/// associated data, so changing the salt, the iterations, or the version
/// breaks the tag instead of weakening the file.
enum SettingsTransfer {
    static let format = "skeen-status-settings"
    static let version = 1
    static let iterations = 600_000
    static let minimumPassphraseLength = 8

    struct Envelope: Codable, Equatable {
        struct KDF: Codable, Equatable {
            var algorithm: String
            var iterations: Int
            var salt: Data
        }
        struct Cipher: Codable, Equatable {
            var algorithm: String
            var nonce: Data
        }
        var format: String
        var version: Int
        var kdf: KDF
        var cipher: Cipher
        /// Ciphertext followed by the 16-byte GCM tag.
        var ciphertext: Data
    }

    static func seal(_ bundle: SettingsBundle, passphrase: String, iterations: Int = iterations) throws -> Data {
        guard passphrase.count >= minimumPassphraseLength else { throw SettingsTransferError.weakPassphrase }
        let salt = randomBytes(16)
        let nonce = AES.GCM.Nonce()
        var envelope = Envelope(
            format: format,
            version: version,
            kdf: .init(algorithm: "PBKDF2-HMAC-SHA256", iterations: iterations, salt: salt),
            cipher: .init(algorithm: "AES-256-GCM", nonce: Data(nonce)),
            ciphertext: Data()
        )
        let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let plaintext = try encoder.encode(bundle)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: associatedData(envelope))
        envelope.ciphertext = box.ciphertext + box.tag
        return try encoder.encode(envelope)
    }

    static func open(_ data: Data, passphrase: String) throws -> SettingsBundle {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.format == format else {
            throw SettingsTransferError.notASettingsFile
        }
        guard envelope.version == version,
              envelope.kdf.algorithm == "PBKDF2-HMAC-SHA256",
              envelope.cipher.algorithm == "AES-256-GCM" else {
            throw SettingsTransferError.unsupportedVersion(envelope.version)
        }
        guard (100_000...10_000_000).contains(envelope.kdf.iterations),
              envelope.kdf.salt.count == 16,
              envelope.ciphertext.count > 16 else {
            throw SettingsTransferError.notASettingsFile
        }
        let key = deriveKey(passphrase: passphrase, salt: envelope.kdf.salt, iterations: envelope.kdf.iterations)
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: envelope.cipher.nonce),
                ciphertext: envelope.ciphertext.dropLast(16),
                tag: envelope.ciphertext.suffix(16)
            )
            let plaintext = try AES.GCM.open(box, using: key, authenticating: associatedData(envelope))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SettingsBundle.self, from: plaintext)
        } catch {
            throw SettingsTransferError.wrongPassphrase
        }
    }

    /// The header fields that must not change, in a fixed byte form.
    private static func associatedData(_ envelope: Envelope) -> Data {
        Data("\(envelope.format)|\(envelope.version)|\(envelope.kdf.algorithm)|\(envelope.kdf.iterations)|\(envelope.kdf.salt.base64EncodedString())|\(envelope.cipher.algorithm)".utf8)
    }

    static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return SymmetricKey(data: derived)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "no system randomness")
        return Data(bytes)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
