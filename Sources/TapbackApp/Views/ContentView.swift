import AppKit
import SwiftTerm
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var serverManager: ServerManager
    @State private var showingAddSession = false
    @State private var showingProxySettings = false
    @State private var editingSession: Session?

    var body: some View {
        ZStack {
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
                                .contextMenu {
                                    Button("Edit") {
                                        editingSession = session
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        sessionManager.removeSession(id: session.id)
                                    }
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

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(serverManager.serverURL, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy URL")

                            if !serverManager.proxyPorts.isEmpty {
                                Text("Proxy: \(serverManager.proxyPorts.count) ports")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.orange)
                            }

                            Text(serverManager.pinEnabled ? "PIN: \(serverManager.pin)" : "PIN: OFF")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()

                            Text("\(serverManager.connectedClients) connected")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Server stopped")
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(serverManager.pinEnabled ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text("PIN")
                                Toggle("", isOn: $serverManager.pinEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }

                            Button("Proxy Settings") {
                                showingProxySettings = true
                            }

                            Text("\(serverManager.proxyPorts.count) ports")
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

                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Session detail
                    if let activeId = sessionManager.activeSessionId,
                       let session = sessionManager.sessions.first(where: { $0.id == activeId })
                    {
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
            .disabled(showingAddSession)

            if showingAddSession {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingAddSession = false
                    }

                AddSessionView(isPresented: $showingAddSession)
                    .environmentObject(sessionManager)
            }

            if showingProxySettings {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingProxySettings = false
                    }

                ProxySettingsView(isPresented: $showingProxySettings)
                    .environmentObject(serverManager)
            }

            if let session = editingSession {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        editingSession = nil
                    }

                EditSessionView(session: session, isPresented: Binding(
                    get: { editingSession != nil },
                    set: { if !$0 { editingSession = nil } }
                ))
                .environmentObject(sessionManager)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
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

    var body: some View {
        if let tmuxSession = session.tmuxSession {
            TerminalContainerView(tmuxSession: tmuxSession)
                .id(session.id)
        } else {
            Text("No tmux session")
                .foregroundColor(.secondary)
        }
    }
}

struct TerminalContainerView: NSViewRepresentable {
    let tmuxSession: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.processDelegate = context.coordinator

        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.nativeForegroundColor = NSColor.white
        terminalView.nativeBackgroundColor = NSColor.black
        terminalView.getTerminal().setCursorStyle(.blinkBlock)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var envDict = ProcessInfo.processInfo.environment
        envDict["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (envDict["PATH"] ?? "")
        envDict["LANG"] = "en_US.UTF-8"
        envDict["LC_ALL"] = "en_US.UTF-8"
        envDict["TERM"] = "xterm-256color"
        let env = envDict.map { "\($0.key)=\($0.value)" }
        terminalView.startProcess(executable: shell, args: ["-l", "-c", "tmux set-option -g default-terminal 'xterm-256color' \\; attach -t \(tmuxSession)"], environment: env)

        return terminalView
    }

    func updateNSView(_: LocalProcessTerminalView, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func processTerminated(source _: TerminalView, exitCode _: Int32?) {}
        func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {}
        func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {}
        func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {}
    }
}

class FocusableNSTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        onFocusChange?(true)
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        onFocusChange?(false)
        return super.resignFirstResponder()
    }

    override var acceptsFirstResponder: Bool { true }
}

struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var autoFocus: Bool = true

    func makeNSView(context: Context) -> FocusableNSTextField {
        let textField = FocusableNSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.isBordered = true
        textField.isBezeled = true
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .exterior

        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textField.window?.makeFirstResponder(textField)
            }
        }

        return textField
    }

    func updateNSView(_ nsView: FocusableNSTextField, context _: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField

        init(_ parent: FocusableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

enum SessionMode: String, CaseIterable {
    case create = "新規作成"
    case watch = "既存を監視"
}

struct AddSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool

    @State private var mode: SessionMode = .create
    @State private var name = ""
    @State private var type: SessionType = .claudeCode
    @State private var tmuxSession = ""
    @State private var discoveredSessions: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Session")
                .font(.headline)

            Picker("", selection: $mode) {
                ForEach(SessionMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name:")
                        .frame(width: 100, alignment: .trailing)
                    FocusableTextField(text: $name, placeholder: "Session name")
                        .frame(height: 22)
                }

                GridRow {
                    Text("Type:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $type) {
                        ForEach(SessionType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .labelsHidden()
                }

                if mode == .watch {
                    GridRow {
                        Text("tmux Session:")
                            .frame(width: 100, alignment: .trailing)
                        HStack {
                            Picker("", selection: $tmuxSession) {
                                Text("Select...").tag("")
                                ForEach(discoveredSessions, id: \.self) { session in
                                    Text(session).tag(session)
                                }
                            }
                            .labelsHidden()

                            Button("Refresh") {
                                Task {
                                    discoveredSessions = await sessionManager.discoverSessions().compactMap(\.tmuxSession)
                                }
                            }
                        }
                    }
                }
            }

            Spacer().frame(height: 8)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    if mode == .create {
                        Task {
                            await sessionManager.addManagedSession(
                                name: name.isEmpty ? type.rawValue : name,
                                type: type
                            )
                            isPresented = false
                        }
                    } else {
                        let session = Session(
                            name: name.isEmpty ? tmuxSession : name,
                            type: type,
                            tmuxSession: tmuxSession.isEmpty ? nil : tmuxSession,
                            isActive: true,
                            isManaged: false
                        )
                        sessionManager.addSession(session)
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .watch && tmuxSession.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .task {
            discoveredSessions = await sessionManager.discoverSessions().compactMap(\.tmuxSession)
        }
    }
}

struct ProxySettingsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @Binding var isPresented: Bool

    @State private var newTargetPort = ""
    @State private var newExternalPort = ""

    var sortedPorts: [(targetPort: Int, externalPort: Int)] {
        serverManager.proxyPorts.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Proxy Port Settings")
                .font(.headline)

            Text("localhost → external")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(sortedPorts, id: \.targetPort) { item in
                    HStack {
                        Text("localhost:\(item.targetPort)")
                            .font(.system(.body, design: .monospaced))
                        Text("→")
                            .foregroundColor(.secondary)
                        Text(":\(item.externalPort)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.orange)

                        Spacer()

                        Button(action: {
                            serverManager.proxyPorts.removeValue(forKey: item.targetPort)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }

                if sortedPorts.isEmpty {
                    Text("No proxy ports configured")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }

            Divider()

            HStack {
                TextField("Target", text: $newTargetPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("→")
                    .foregroundColor(.secondary)
                TextField("External", text: $newExternalPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                Button("Add") {
                    if let target = Int(newTargetPort), let external = Int(newExternalPort) {
                        serverManager.proxyPorts[target] = external
                        newTargetPort = ""
                        newExternalPort = ""
                    }
                }
                .disabled(Int(newTargetPort) == nil || Int(newExternalPort) == nil)
            }

            Spacer().frame(height: 8)

            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

struct EditSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    let session: Session
    @Binding var isPresented: Bool

    @State private var name: String
    @State private var type: SessionType
    @State private var tmuxSession: String
    @State private var discoveredSessions: [String] = []

    init(session: Session, isPresented: Binding<Bool>) {
        self.session = session
        _isPresented = isPresented
        _name = State(initialValue: session.name)
        _type = State(initialValue: session.type)
        _tmuxSession = State(initialValue: session.tmuxSession ?? "")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Session")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Session name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Type:")
                        .frame(width: 100, alignment: .trailing)
                    Picker("", selection: $type) {
                        ForEach(SessionType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .labelsHidden()
                }

                GridRow {
                    Text("tmux Session:")
                        .frame(width: 100, alignment: .trailing)
                    HStack {
                        Picker("", selection: $tmuxSession) {
                            Text("Select...").tag("")
                            ForEach(discoveredSessions, id: \.self) { session in
                                Text(session).tag(session)
                            }
                        }
                        .labelsHidden()

                        Button("Refresh") {
                            Task {
                                discoveredSessions = await sessionManager.discoverSessions().compactMap(\.tmuxSession)
                            }
                        }
                    }
                }
            }

            Spacer().frame(height: 8)

            HStack {
                Button("Delete", role: .destructive) {
                    sessionManager.removeSession(id: session.id)
                    isPresented = false
                }
                .foregroundColor(.red)

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    sessionManager.updateSession(
                        id: session.id,
                        name: name.isEmpty ? tmuxSession : name,
                        type: type,
                        tmuxSession: tmuxSession.isEmpty ? nil : tmuxSession
                    )
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tmuxSession.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .task {
            discoveredSessions = await sessionManager.discoverSessions().compactMap(\.tmuxSession)
            if !discoveredSessions.contains(tmuxSession), !tmuxSession.isEmpty {
                discoveredSessions.insert(tmuxSession, at: 0)
            }
        }
    }
}
