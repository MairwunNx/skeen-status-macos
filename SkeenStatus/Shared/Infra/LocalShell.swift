import ComposableArchitecture
import Foundation

struct LocalCommandResult: Equatable, Sendable {
    var exitCode: Int32
    var output: String
}

/// Runs scenario commands locally on the Mac via `/bin/sh -c`, never on the
/// router.
@DependencyClient
struct LocalShell: Sendable {
    var run: @Sendable (_ command: String) async -> LocalCommandResult = { _ in
        LocalCommandResult(exitCode: 0, output: "")
    }
}

extension LocalShell: DependencyKey {
    static let liveValue = LocalShell(run: { command in
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: LocalCommandResult(
                        exitCode: -1,
                        output: "failed to launch: \(error.localizedDescription)"
                    ))
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: LocalCommandResult(
                    exitCode: process.terminationStatus,
                    output: String(data: data, encoding: .utf8) ?? ""
                ))
            }
        }
    })

    static let testValue = LocalShell()
}

extension DependencyValues {
    var localShell: LocalShell {
        get { self[LocalShell.self] }
        set { self[LocalShell.self] = newValue }
    }
}
