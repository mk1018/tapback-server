import Foundation

enum TmuxHelper {
    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        return env
    }

    static func capture(session: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["tmux", "capture-pane", "-t", "\(session):0.0", "-p", "-S", "-300"]
                process.environment = environment
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    static func sendKeys(session: String, text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if !text.isEmpty {
                    let textProcess = Process()
                    textProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    textProcess.arguments = ["tmux", "send-keys", "-t", "\(session):0.0", "-l", text]
                    textProcess.environment = environment
                    textProcess.standardOutput = FileHandle.nullDevice
                    textProcess.standardError = FileHandle.nullDevice
                    do {
                        try textProcess.run()
                        textProcess.waitUntilExit()
                    } catch {}
                }

                let enterProcess = Process()
                enterProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                enterProcess.arguments = ["tmux", "send-keys", "-t", "\(session):0.0", "Enter"]
                enterProcess.environment = environment
                enterProcess.standardOutput = FileHandle.nullDevice
                enterProcess.standardError = FileHandle.nullDevice
                do {
                    try enterProcess.run()
                    enterProcess.waitUntilExit()
                } catch {}

                continuation.resume()
            }
        }
    }

    static func listSessions() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["tmux", "list-sessions", "-F", "#{session_name}"]
                process.environment = environment
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output.split(separator: "\n").map(String.init))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    static func createSession(name: String, directory: String? = nil) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.environment = environment

                var args = ["tmux", "new-session", "-d", "-s", name]
                if let dir = directory {
                    args += ["-c", dir]
                }
                process.arguments = args
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    static func killSession(name: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["tmux", "kill-session", "-t", name]
                process.environment = environment
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {}

                continuation.resume()
            }
        }
    }

    static func getCurrentPath(session: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["tmux", "display-message", "-t", "\(session):0.0", "-p", "#{pane_current_path}"]
                process.environment = environment
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output?.isEmpty == false ? output : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
