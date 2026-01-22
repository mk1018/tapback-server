import AppKit
import SwiftTerm
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var showingProxySettings = false
    @State private var showingQuickButtonSettings = false
    @State private var tmuxSessions: [String] = []
    @State private var selectedSession: String?

    var body: some View {
        ZStack {
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

                        Button("Quick Buttons") {
                            showingQuickButtonSettings = true
                        }

                        Text("\(serverManager.quickButtons.count) buttons")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(serverManager.isRunning ? "Stop" : "Start") {
                        if serverManager.isRunning {
                            serverManager.stop()
                        } else {
                            serverManager.start()
                        }
                    }

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Session tabs
                if !tmuxSessions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tmuxSessions, id: \.self) { session in
                                Button(action: { selectedSession = session }) {
                                    Text(session)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedSession == session ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                        .foregroundColor(selectedSession == session ? .white : .primary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()
                }

                // Terminal view
                if let session = selectedSession {
                    TerminalContainerView(tmuxSession: session)
                        .id(session)
                } else {
                    VStack {
                        Spacer()
                        if tmuxSessions.isEmpty {
                            Text("No tmux sessions found")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Select a session")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
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

            if showingQuickButtonSettings {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingQuickButtonSettings = false
                    }

                QuickButtonSettingsView(isPresented: $showingQuickButtonSettings)
                    .environmentObject(serverManager)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await refreshSessions()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            Task { await refreshSessions() }
        }
    }

    private func refreshSessions() async {
        let sessions = await TmuxHelper.listSessions()
        await MainActor.run {
            tmuxSessions = sessions
            if selectedSession == nil, let first = sessions.first {
                selectedSession = first
            }
            if let selected = selectedSession, !sessions.contains(selected) {
                selectedSession = sessions.first
            }
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

struct QuickButtonSettingsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @Binding var isPresented: Bool

    @State private var newLabel = ""
    @State private var newCommand = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Quick Button Settings")
                .font(.headline)

            Text("Custom commands for mobile")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(serverManager.quickButtons) { button in
                    HStack {
                        Text(button.label)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(button.command)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Button(action: {
                            serverManager.quickButtons.removeAll { $0.id == button.id }
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

                if serverManager.quickButtons.isEmpty {
                    Text("No custom buttons configured")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }

            Divider()

            HStack {
                TextField("Label", text: $newLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                TextField("Command (e.g. /commit)", text: $newCommand)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    if !newLabel.isEmpty, !newCommand.isEmpty {
                        serverManager.quickButtons.append(
                            QuickButton(label: newLabel, command: newCommand)
                        )
                        newLabel = ""
                        newCommand = ""
                    }
                }
                .disabled(newLabel.isEmpty || newCommand.isEmpty)
            }

            Spacer().frame(height: 8)

            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}
