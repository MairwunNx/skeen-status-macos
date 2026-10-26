import Foundation
import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import Citadel

nonisolated enum SSHSessionError: Error, Sendable {
    case notConnected
    case timeout
    case stopped
    case disconnected
}

/// Owns one long-lived interactive PTY channel and serializes command access.
///
/// A single background loop keeps the connection alive (auto-reconnect with
/// backoff), runs the configured post-connect commands after each (re)connect,
/// then becomes ready for status polling. Commands are written to the same
/// stdin and read back until a per-command completion marker is seen.
actor SSHSession {
    private var connection: SSHConnection?
    private var client: SSHClient?
    private var writer: TTYStdinWriter?

    private var buffer = ""
    private var ready = false
    private var stopped = false

    private var sessionTask: Task<Void, Never>?

    private struct Pending {
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

    func start(connection: SSHConnection) {
        self.connection = connection
        stopped = false
        if sessionTask == nil {
            sessionTask = Task { await self.runLoop() }
        }
    }

    func update(connection: SSHConnection) async {
        guard connection != self.connection else { return }
        self.connection = connection
        await dropConnection()
    }

    func stop() async {
        stopped = true
        ready = false
        failPending(SSHSessionError.stopped)
        sessionTask?.cancel()
        sessionTask = nil
        writer = nil
        if let client {
            try? await client.close()
            self.client = nil
        }
    }

    // MARK: Public command API

    func runWhenReady(
        _ command: String,
        readyTimeout: Duration,
        commandTimeout: Duration
    ) async throws -> String {
        try await waitUntilReady(timeout: readyTimeout)
        return try await run(command, timeout: commandTimeout)
    }

    /// Sends a command without a completion marker and returns whatever the
    /// remote prints until output stays quiet for `settle` (or `timeout` hits).
    ///
    /// Used for post-connect commands such as `exec sh`: before a real shell
    /// exists the Keenetic CLI does not behave like POSIX `sh`, so the marker
    /// echo cannot run and we must rely on output quiescence instead.
    func runRaw(_ command: String, settle: Duration, timeout: Duration) async throws -> String {
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

    func run(_ command: String, timeout: Duration) async throws -> String {
        await acquire()
        defer { release() }

        guard let writer else { throw SSHSessionError.notConnected }
        let begin = makeMarker()
        let end = makeMarker()
        buffer = ""
        let payload = wrapCommand(command, begin: begin, end: end)

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.failPending(SSHSessionError.timeout)
        }
        defer { timeoutTask.cancel() }

        try await writer.write(ByteBuffer(string: payload))

        let raw = try await withCheckedThrowingContinuation { continuation in
            self.pending = Pending(begin: begin, end: end, continuation: continuation)
            if let output = extractBetween(from: buffer, begin: begin, end: end) {
                self.pending = nil
                self.buffer = ""
                continuation.resume(returning: output)
            }
        }
        return cleanOutput(raw)
    }

    // MARK: Readiness

    private func waitUntilReady(timeout: Duration) async throws {
        if ready { return }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !ready {
            if stopped { throw SSHSessionError.stopped }
            if ContinuousClock.now >= deadline { throw SSHSessionError.timeout }
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

    private func failPending(_ error: Error) {
        guard let pending else { return }
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
            guard let connection else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            do {
                log("SSH connecting to \(connection.host):\(connection.port)")
                let client = try await SSHClient.connect(
                    host: connection.host,
                    port: connection.port,
                    authenticationMethod: .passwordBased(
                        username: connection.username,
                        password: connection.password
                    ),
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never,
                    connectTimeout: .seconds(15)
                )
                self.client = client
                backoff = 1.0
                try await openShell(client: client, connection: connection)
                log("SSH session closed")
            } catch {
                log("SSH error: \(error)")
            }

            ready = false
            writer = nil
            failPending(SSHSessionError.disconnected)
            if let client {
                try? await client.close()
                self.client = nil
            }

            if stopped { break }
            let wait = backoff
            backoff = min(backoff * 2, 30)
            log("SSH reconnecting in \(Int(wait))s")
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func openShell(client: SSHClient, connection: SSHConnection) async throws {
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm",
            terminalCharacterWidth: 120,
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
        ready = true
        log("SSH session ready")
    }

    private func dropConnection() async {
        ready = false
        writer = nil
        failPending(SSHSessionError.disconnected)
        if let client {
            try? await client.close()
            self.client = nil
        }
    }

    // MARK: One-shot connectivity test

    static func test(connection: SSHConnection) async -> Result<String, Error> {
        do {
            let client = try await SSHClient.connect(
                host: connection.host,
                port: connection.port,
                authenticationMethod: .passwordBased(
                    username: connection.username,
                    password: connection.password
                ),
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                connectTimeout: .seconds(15)
            )
            try? await client.close()
            return .success("Подключение успешно: \(connection.host):\(connection.port)")
        } catch {
            return .failure(error)
        }
    }
}
