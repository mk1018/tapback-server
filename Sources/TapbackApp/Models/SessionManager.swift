import Combine
import Foundation

@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = [] {
        didSet {
            if !isLoading { save() }
        }
    }

    @Published var activeSessionId: UUID?

    private var outputCache: [UUID: String] = [:]
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private let storageKey = "tapback_sessions"
    private var isLoading = false

    init() {
        load()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        isLoading = true
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Session].self, from: data)
        {
            sessions = saved
            for session in sessions where session.isActive {
                startPolling(for: session.id)
            }
        }
        isLoading = false
    }

    func addSession(_ session: Session) {
        sessions.append(session)
        if session.isActive {
            startPolling(for: session.id)
        }
    }

    func addManagedSession(name: String, type: SessionType) async {
        let tmuxSessionName = "tapback-\(UUID().uuidString.prefix(8))"
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let success = await TmuxHelper.createSession(name: tmuxSessionName, directory: homeDir)
        if success {
            let session = Session(
                name: name,
                type: type,
                tmuxSession: tmuxSessionName,
                isActive: true,
                isManaged: true
            )
            sessions.append(session)
            startPolling(for: session.id)
        }
    }

    func removeSession(id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        stopPolling(for: id)

        if session.isManaged, let tmuxSession = session.tmuxSession {
            Task {
                await TmuxHelper.killSession(name: tmuxSession)
            }
        }

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

    func updateSession(id: UUID, name: String, type: SessionType, tmuxSession: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = sessions[index].isActive
        let oldTmuxSession = sessions[index].tmuxSession

        sessions[index].name = name
        sessions[index].type = type
        sessions[index].tmuxSession = tmuxSession

        if wasActive, oldTmuxSession != tmuxSession {
            stopPolling(for: id)
            if tmuxSession != nil {
                startPolling(for: id)
            }
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
