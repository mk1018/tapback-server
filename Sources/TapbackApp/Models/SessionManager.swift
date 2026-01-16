import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionId: UUID?

    private var outputCache: [UUID: String] = [:]
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]

    func addSession(_ session: Session) {
        sessions.append(session)
        if session.isActive {
            startPolling(for: session.id)
        }
    }

    func removeSession(id: UUID) {
        stopPolling(for: id)
        sessions.removeAll { $0.id == id }
    }

    func toggleSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].isActive.toggle()
        if sessions[index].isActive {
            startPolling(for: id)
        } else {
            stopPolling(for: id)
        }
    }

    func getOutput(for id: UUID) -> String {
        outputCache[id] ?? ""
    }

    func sendInput(_ text: String, to id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }),
              let tmuxSession = session.tmuxSession else { return }

        Task {
            await TmuxHelper.sendKeys(session: tmuxSession, text: text)
        }
    }

    private func startPolling(for id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }),
              let tmuxSession = session.tmuxSession else { return }

        pollingTasks[id] = Task {
            while !Task.isCancelled {
                let output = await TmuxHelper.capture(session: tmuxSession)
                await MainActor.run {
                    self.outputCache[id] = output
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }

    private func stopPolling(for id: UUID) {
        pollingTasks[id]?.cancel()
        pollingTasks.removeValue(forKey: id)
    }

    func discoverSessions() async -> [Session] {
        let tmuxSessions = await TmuxHelper.listSessions()
        return tmuxSessions.map { name in
            Session(
                name: name,
                type: name.contains("claude") ? .claudeCode : .custom,
                tmuxSession: name
            )
        }
    }
}
