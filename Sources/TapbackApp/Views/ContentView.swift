import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var serverManager: ServerManager
    @State private var showingAddSession = false

    var body: some View {
        HSplitView {
            // Left: Session list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Sessions")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingAddSession = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()

                Divider()

                List(selection: $sessionManager.activeSessionId) {
                    ForEach(sessionManager.sessions) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            sessionManager.removeSession(id: sessionManager.sessions[index].id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, maxWidth: 300)

            // Right: Main content
            VStack(spacing: 0) {
                // Server status bar
                HStack {
                    Circle()
                        .fill(serverManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    if serverManager.isRunning {
                        Text(serverManager.serverURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Text("PIN: \(serverManager.pin)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text("\(serverManager.connectedClients) connected")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Server stopped")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(serverManager.isRunning ? "Stop" : "Start") {
                        if serverManager.isRunning {
                            serverManager.stop()
                        } else {
                            serverManager.start(sessionManager: sessionManager)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Session detail
                if let activeId = sessionManager.activeSessionId,
                   let session = sessionManager.sessions.first(where: { $0.id == activeId }) {
                    SessionDetailView(session: session)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a session")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showingAddSession) {
            AddSessionView()
        }
    }
}

struct SessionRowView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        HStack {
            Circle()
                .fill(session.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading) {
                Text(session.name)
                    .font(.body)
                Text(session.type.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { session.isActive },
                set: { _ in sessionManager.toggleSession(id: session.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetailView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollView {
                Text(sessionManager.getOutput(for: session.id))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Input
            HStack {
                TextField("Input...", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sessionManager.sendInput(input, to: session.id)
                        input = ""
                    }

                Button("Send") {
                    sessionManager.sendInput(input, to: session.id)
                    input = ""
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
        }
    }
}

struct AddSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var type: SessionType = .claudeCode
    @State private var tmuxSession = ""
    @State private var discoveredSessions: [String] = []

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Session")
                .font(.headline)

            Form {
                TextField("Name", text: $name)

                Picker("Type", selection: $type) {
                    ForEach(SessionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                Picker("tmux Session", selection: $tmuxSession) {
                    Text("Select...").tag("")
                    ForEach(discoveredSessions, id: \.self) { session in
                        Text(session).tag(session)
                    }
                }

                Button("Refresh Sessions") {
                    Task {
                        discoveredSessions = await sessionManager.discoverSessions().compactMap { $0.tmuxSession }
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    let session = Session(
                        name: name.isEmpty ? tmuxSession : name,
                        type: type,
                        tmuxSession: tmuxSession.isEmpty ? nil : tmuxSession,
                        isActive: true
                    )
                    sessionManager.addSession(session)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tmuxSession.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .task {
            discoveredSessions = await sessionManager.discoverSessions().compactMap { $0.tmuxSession }
        }
    }
}
