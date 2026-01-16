import Foundation

enum TmuxHelper {
    static func capture(session: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["tmux", "capture-pane", "-t", session, "-p", "-S", "-100"]
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
                // Send text
                if !text.isEmpty {
                    let textProcess = Process()
                    textProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    textProcess.arguments = ["tmux", "send-keys", "-t", session, "-l", text]
                    textProcess.standardOutput = FileHandle.nullDevice
                    textProcess.standardError = FileHandle.nullDevice

                    do {
                        try textProcess.run()
                        textProcess.waitUntilExit()
                    } catch {}
                }

                // Send Enter
                let enterProcess = Process()
                enterProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                enterProcess.arguments = ["tmux", "send-keys", "-t", session, "Enter"]
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
}
