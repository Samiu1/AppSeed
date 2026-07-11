import Foundation

struct ProcessFailure: LocalizedError {
    let tool: String
    let status: Int32
    let stderr: String

    var errorDescription: String? {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(tool) failed (exit \(status))\(detail.isEmpty ? "" : ": \(detail)")"
    }
}

/// Thin wrapper over Process for the pipeline's command-line steps
/// (xattr, codesign, sips, iconutil, lsregister) with captured stderr so
/// every failure is reportable to the user verbatim.
enum ProcessRunner {
    @discardableResult
    static func run(_ toolPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProcessFailure(
                tool: (toolPath as NSString).lastPathComponent,
                status: process.terminationStatus,
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
