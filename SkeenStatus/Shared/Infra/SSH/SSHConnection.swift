import Foundation

/// Immutable connection description handed to the SSH session actor.
struct SSHConnection: Sendable, Equatable {
    var host: String
    var port: Int
    var username: String
    var password: String
    var postConnectCommands: [String]
    /// The host key accepted earlier, in OpenSSH form. `nil` trusts the first
    /// key the router shows, and the session reports it so it can be pinned.
    var trustedHostKey: String?
}
