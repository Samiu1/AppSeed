import Foundation

/// Hidden CLI mode for scripted creation and end-to-end testing without the
/// HUD or hotkey:
///
///   AppSeed --make <url> [--name <name>] [--out <directory>] [--overwrite]
///
/// Collisions auto-rename by default (pass --overwrite to replace). Exits the
/// process when a --make invocation is present; returns otherwise.
enum HeadlessFactoryCLI {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--make") else { return }

        do {
            let request = try parse(arguments)
            exit(execute(request, overwrite: arguments.contains("--overwrite")))
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func parse(_ arguments: [String]) throws -> FactoryRequest {
        var rawURL: String?
        var rawName: String?
        var outDirectory: String?

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--make":
                index += 1
                rawURL = value(arguments, at: index)
            case "--name":
                index += 1
                rawName = value(arguments, at: index)
            case "--out":
                index += 1
                outDirectory = value(arguments, at: index)
            case "--overwrite":
                break
            default:
                fail("Unknown argument: \(arguments[index])\nUsage: AppSeed --make <url> [--name <name>] [--out <dir>] [--overwrite]")
            }
            index += 1
        }

        guard let rawURL else { fail("--make requires a URL") }
        let url = try InputNormalizer.normalizeURL(rawURL)
        let name = try InputNormalizer.sanitizeAppName(
            rawName ?? DomainUtils.suggestedAppName(forHost: url.host ?? "")
        )
        let destination = outDirectory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? AppFactory.defaultInstallDirectory
        return FactoryRequest(url: url, appName: name, destinationDirectory: destination)
    }

    private static func execute(_ request: FactoryRequest, overwrite: Bool) -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0

        Task.detached {
            let factory = AppFactory(
                progress: { message in print("• \(message)") },
                resolveCollision: { _ in overwrite ? .overwrite : .autoRename }
            )
            do {
                let installed = try await factory.build(request)
                print("Created: \(installed.path)")
            } catch {
                FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
                exitCode = 1
            }
            semaphore.signal()
        }

        semaphore.wait()
        return exitCode
    }

    private static func value(_ arguments: [String], at index: Int) -> String {
        guard index < arguments.count else { fail("Missing value for \(arguments[index - 1])") }
        return arguments[index]
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(2)
    }
}
