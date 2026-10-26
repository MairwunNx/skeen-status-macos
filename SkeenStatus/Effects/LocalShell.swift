import Foundation

nonisolated struct LocalCommandResult: Sendable {
    var exitCode: Int32
    var output: String
}

/// Runs scenario commands locally on the Mac via `/bin/sh -c`.
nonisolated enum LocalShell {
    static func run(_ command: String) async -> LocalCommandResult {
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
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: LocalCommandResult(
                    exitCode: process.terminationStatus,
                    output: output
                ))
            }
        }
    }
}
