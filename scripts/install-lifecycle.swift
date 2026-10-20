import AppKit
import Foundation

// A short-lived installer helper. Only targets the supplied bundle identifier;
// never force-terminates processes or changes preferences/history/login items.
enum InstallError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let text): return text } }
}

func waitFor(_ predicate: () -> Bool, seconds: TimeInterval = 15) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate(), Date() < deadline {
        RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.05)))
    }
    return predicate()
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2 else { throw InstallError.message("Expected quit BUNDLE_ID or open APP_PATH BUNDLE_ID") }
    switch args[0] {
    case "quit":
        guard args.count == 2, !args[1].isEmpty else { throw InstallError.message("Expected quit BUNDLE_ID") }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).filter { !$0.isTerminated }
        for app in apps where !app.isTerminated {
            guard app.terminate() || app.isTerminated else {
                throw InstallError.message("Quit request was refused by PID \(app.processIdentifier). Quit from the app's menu and retry.")
            }
        }
        guard waitFor({ apps.allSatisfy { $0.isTerminated } }) else {
            throw InstallError.message("Timed out waiting for a normal quit; installed files were not replaced.")
        }
        print(apps.count)
    case "open":
        guard args.count == 3 else { throw InstallError.message("Expected open APP_PATH BUNDLE_ID") }
        let url = URL(fileURLWithPath: args[1]).standardizedFileURL
        let configuration = NSWorkspace.OpenConfiguration()
        var result: Result<NSRunningApplication, Error>?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error { result = .failure(error) }
            else if let app { result = .success(app) }
            else { result = .failure(InstallError.message("macOS returned no application.")) }
        }
        guard waitFor({ result != nil }), let result else { throw InstallError.message("Timed out waiting for macOS to launch the app.") }
        let app = try result.get()
        guard app.bundleIdentifier == args[2], app.bundleURL?.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path else {
            throw InstallError.message("macOS opened a different application copy. Open the installed path manually.")
        }
        print("Launched: \(url.path)")
    default: throw InstallError.message("Unknown installer lifecycle command")
    }
}

do { try run() }
catch { fputs("Mac Buddy installer: \(error)\n", stderr); exit(1) }
