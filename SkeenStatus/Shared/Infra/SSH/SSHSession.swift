import Foundation
import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import Citadel

enum SSHSessionError: Error, Equatable, Sendable, LocalizedError {
    case noPassword
    case notConnected
    case connectFailed(String)
    case hostKeyChanged
    case noShell
    case timeout
    case stopped
    case disconnected

    var errorDescription: String? {
        switch self {
        case .noPassword: return String(localized: "No SSH password is set")
        case .notConnected: return String(localized: "No SSH session")
        case .connectFailed(let reason): return reason
        case .hostKeyChanged: return String(localized: "The router’s host key changed. If you didn’t replace the router, someone may be intercepting the connection")
        case .noShell: return String(localized: "No POSIX shell after the post-connect commands. Check “exec sh”")
        case .timeout: return String(localized: "The router didn’t answer in time")
        case .stopped: return String(localized: "The SSH session is stopped")
        case .disconnected: return String(localized: "The SSH connection dropped")
        }
    }
}

/// Turns Citadel and NIO errors into a short Russian reason.
func describeConnectError(_ error: Error) -> String {
    if let error = error as? SSHSessionError { return error.localizedDescription }
    let text = String(describing: error)
    if text.contains("allAuthenticationOptionsFailed") || text.contains("authentication") {
        return String(localized: "The router rejected the login or password")
    }
    if text.contains("connectTimeout") || text.contains("timeout") {
        return String(localized: "The router doesn’t answer")
    }
    if text.contains("connectionRefused") || text.contains("Connection refused") {
        return String(localized: "The router refused the connection. Check the SSH port")
    }
    if text.contains("hostUnreachable") || text.contains("No route") || text.contains("networkUnreachable") {
        return String(localized: "The router is not reachable on the network")
    }
    return text
}

/// Accepts the pinned host key only, or the first key when nothing is pinned
/// yet, and remembers which key the router showed.
private final class HostKeyPin: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let trusted: String?
    private let lock = NSLock()
    private var seenKey: String?

    init(trusted: String?) {
        self.trusted = trusted.flatMap(normalizedHostKey)
    }

    var seen: String? { lock.withLock { seenKey } }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let key = normalizedHostKey(String(openSSHPublicKey: hostKey)) ?? ""
        lock.withLock { seenKey = key }
        if let trusted, trusted != key {
            validationCompletePromise.fail(SSHSessionError.hostKeyChanged)
        } else {
            validationCompletePromise.succeed(())
        }
    }
}

/// Keeps the key type and the base64 body, dropping any trailing comment.
func normalizedHostKey(_ key: String) -> String? {
    let parts = key.split(whereSeparator: \.isWhitespace)
    guard parts.count >= 2 else { return nil }
    return "\(parts[0]) \(parts[1])"
}

/// Owns one long-lived interactive PTY channel and serializes command access.
///
/// A single background loop keeps the connection alive (auto-reconnect with
/// backoff), runs the configured post-connect commands after each (re)connect,
/// checks that a POSIX shell answers, then becomes ready. Commands are written
/// to the same stdin and read back until a per-command completion marker shows.
actor SSHSession {
    private var connection: SSHConnection?
    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var hostKeyPin: HostKeyPin?

    private var buffer = ""
    private var ready = false
    private var stopped = false
    private var lastConnectError: SSHSessionError?
    /// Bumped on every config change or forced reconnect, so a sleeping
    /// backoff wakes up at once.
    private var generation = 0

    private var sessionTask: Task<Void, Never>?

    private struct Pending {
        let id: UUID
        let begin: String
        let end: String
        let continuation: CheckedContinuation<String, Error>
    }
    private var pending: Pending?

    private var commandLocked = false
    private var lockWaiters: [CheckedContinuation<Void, Never>] = []

    private let log: @Sendable (String) -> Void

    init(log: @escaping @Sendable (String) -> Void) {
        self.log = log
    }

    // MARK: Lifecycle

    /// Starts the session on first use and reconnects when the connection
    /// changes. Pinning the key the router just showed does not reconnect.
    func configure(_ connection: SSHConnection) async {
        let old = self.connection
        self.connection = connection
        stopped = false
        if sessionTask == nil {
            sessionTask = Task { await self.runLoop() }
            return
        }
        guard var comparable = old else { return }
        if comparable.trustedHostKey == nil, connection.trustedHostKey == hostKeyPin?.seen {
            comparable.trustedHostKey = connection.trustedHostKey
        }
        if comparable != connection {
            await reconnect()
        }
    }

    /// Drops the current connection so the loop dials again right away, e.g.
    /// after the Mac wakes up.
    func reconnect() async {
        generation += 1
        await dropConnection()
    }

    func stop() async {
        stopped = true
        generation += 1
        sessionTask?.cancel()
        sessionTask = nil
        await dropConnection(error: .stopped)
    }

    /// The host key the router showed on the current connection.
    func hostKey() -> String? {
        hostKeyPin?.seen
    }

    // MARK: Public command API

    func runWhenReady(_ command: String, readyTimeout: Duration, commandTimeout: Duration) async throws -> String {
        try await waitUntilReady(timeout: readyTimeout)
        return try await run(command, timeout: commandTimeout)
    }

    /// Sends a command without a completion marker and returns whatever the
    /// remote prints until output stays quiet for `settle` (or `timeout` hits).
    ///
    /// Used for post-connect commands such as `exec sh`: before a real shell
    /// exists the Keenetic CLI does not behave like POSIX `sh`, so the marker
    /// echo cannot run and we must rely on output quiescence instead.
    private func runRaw(_ command: String, settle: Duration, timeout: Duration) async throws -> String {
        await acquire()
        defer { release() }

        guard let writer else { throw SSHSessionError.notConnected }
        buffer = ""
        try await writer.write(ByteBuffer(string: command + "\n"))

        let deadline = ContinuousClock.now.advanced(by: timeout)
        var lastCount = -1
        var lastChange = ContinuousClock.now
        while ContinuousClock.now < deadline {
            if stopped { throw SSHSessionError.stopped }
            let count = buffer.count
            if count != lastCount {
                lastCount = count
                lastChange = ContinuousClock.now
            } else if ContinuousClock.now >= lastChange.advanced(by: settle) {
                break
            }
            try await Task.sleep(for: .milliseconds(120))
        }

        let output = buffer
        buffer = ""
        return output
    }

    private func run(_ command: String, timeout: Duration) async throws -> String {
        await acquire()
        defer { release() }

        guard let writer else { throw SSHSessionError.notConnected }
        let id = UUID()
        let begin = makeMarker()
        let end = makeMarker()
        buffer = ""
        let payload = ByteBuffer(string: wrapCommand(command, begin: begin, end: end))

        // The pending slot exists before the write and the timer start, so a
        // timeout can never fire into an empty slot and leave the call hanging.
        let raw = try await withCheckedThrowingContinuation { continuation in
            pending = Pending(id: id, begin: begin, end: end, continuation: continuation)
            Task {
                try? await Task.sleep(for: timeout)
                await self.failPending(id: id, SSHSessionError.timeout)
            }
            Task {
                do {
                    try await writer.write(payload)
                } catch {
                    await self.failPending(id: id, error)
                }
            }
        }
        return cleanOutput(raw)
    }

    // MARK: Readiness

    private func waitUntilReady(timeout: Duration) async throws {
        if ready { return }
        guard connection?.password.isEmpty == false else { throw SSHSessionError.noPassword }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !ready {
            if stopped { throw SSHSessionError.stopped }
            if ContinuousClock.now >= deadline { throw lastConnectError ?? SSHSessionError.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: Reading

    private func handleChunk(_ text: String) {
        buffer += text
        guard let pending, let output = extractBetween(from: buffer, begin: pending.begin, end: pending.end) else { return }
        self.pending = nil
        buffer = ""
        pending.continuation.resume(returning: output)
    }

    private func failPending(id: UUID? = nil, _ error: Error) {
        guard let pending, id == nil || pending.id == id else { return }
        self.pending = nil
        buffer = ""
        pending.continuation.resume(throwing: error)
    }

    // MARK: Command serialization

    private func acquire() async {
        if !commandLocked {
            commandLocked = true
            return
        }
        await withCheckedContinuation { lockWaiters.append($0) }
    }

    private func release() {
        if lockWaiters.isEmpty {
            commandLocked = false
        } else {
            lockWaiters.removeFirst().resume()
        }
    }

    // MARK: Connection loop

    private func runLoop() async {
        var backoff = 1.0
        while !stopped {
            guard let connection, !connection.password.isEmpty else {
                lastConnectError = .noPassword
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let startedGeneration = generation
            do {
                log("SSH connecting to \(connection.host):\(connection.port)")
                let pin = HostKeyPin(trusted: connection.trustedHostKey)
                hostKeyPin = pin
                let client = try await SSHClient.connect(
                    host: connection.host,
                    port: connection.port,
                    authenticationMethod: .passwordBased(username: connection.username, password: connection.password),
                    hostKeyValidator: .custom(pin),
                    reconnect: .never,
                    connectTimeout: .seconds(10)
                )
                self.client = client
                backoff = 1.0
                try await openShell(client: client, connection: connection)
                log("SSH session closed")
            } catch {
                let reason = (error as? SSHSessionError) ?? .connectFailed(describeConnectError(error))
                lastConnectError = reason
                log("SSH error: \(error)")
            }

            await dropConnection()
            if stopped { break }

            let wait = backoff
            backoff = min(backoff * 2, 30)
            log("SSH reconnecting in \(Int(wait))s")
            let wakeAt = ContinuousClock.now.advanced(by: .seconds(wait))
            while ContinuousClock.now < wakeAt, generation == startedGeneration, !stopped {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if generation != startedGeneration { backoff = 1.0 }
        }
    }

    private func openShell(client: SSHClient, connection: SSHConnection) async throws {
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm",
            terminalCharacterWidth: 200,
            terminalRowHeight: 40,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([.ECHO: 0])
        )

        try await client.withPTY(request) { @Sendable inbound, outbound in
            await self.setWriter(outbound)
            let setup = Task { await self.runPostConnect(connection: connection) }
            defer { setup.cancel() }
            for try await chunk in inbound {
                switch chunk {
                case .stdout(let bytes), .stderr(let bytes):
                    await self.handleChunk(String(buffer: bytes))
                }
            }
        }
    }

    private func setWriter(_ writer: TTYStdinWriter?) {
        self.writer = writer
    }

    private func runPostConnect(connection: SSHConnection) async {
        try? await Task.sleep(for: .milliseconds(400))
        for command in connection.postConnectCommands {
            do {
                let output = try await runRaw(command, settle: .milliseconds(800), timeout: .seconds(20))
                log("post-connect '\(command)' -> \(cleanOutput(output).prefix(200))")
            } catch {
                log("post-connect '\(command)' failed: \(error)")
            }
        }

        // A marker round trip proves the shell is POSIX before polling starts.
        do {
            let probe = try await run("echo ready", timeout: .seconds(8))
            guard probe.contains("ready") else { throw SSHSessionError.noShell }
            ready = true
            lastConnectError = nil
            log("SSH session ready")
        } catch {
            lastConnectError = .noShell
            log("SSH shell probe failed: \(error)")
            await dropConnection()
        }
    }

    private func dropConnection(error: SSHSessionError = .disconnected) async {
        ready = false
        writer = nil
        failPending(error)
        if let client {
            self.client = nil
            try? await client.close()
        }
    }

    // MARK: One-shot connectivity test

    /// Connects once, checks the login, and returns the router's host key.
    static func test(connection: SSHConnection) async throws -> String {
        guard !connection.password.isEmpty else { throw SSHSessionError.noPassword }
        let pin = HostKeyPin(trusted: connection.trustedHostKey)
        do {
            let client = try await SSHClient.connect(
                host: connection.host,
                port: connection.port,
                authenticationMethod: .passwordBased(username: connection.username, password: connection.password),
                hostKeyValidator: .custom(pin),
                reconnect: .never,
                connectTimeout: .seconds(10)
            )
            try? await client.close()
        } catch {
            if let error = error as? SSHSessionError { throw error }
            if pin.seen != nil, connection.trustedHostKey != nil, pin.seen != normalizedHostKey(connection.trustedHostKey ?? "") {
                throw SSHSessionError.hostKeyChanged
            }
            throw SSHSessionError.connectFailed(describeConnectError(error))
        }
        return pin.seen ?? ""
    }
}
