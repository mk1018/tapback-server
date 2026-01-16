import Foundation

enum SessionType: String, Codable, CaseIterable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case custom = "Custom"
}

struct Session: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: SessionType
    var tmuxSession: String?
    var port: Int?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        type: SessionType,
        tmuxSession: String? = nil,
        port: Int? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.tmuxSession = tmuxSession
        self.port = port
        self.isActive = isActive
    }
}
