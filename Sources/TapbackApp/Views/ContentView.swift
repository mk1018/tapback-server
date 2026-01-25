import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var showingProxySettings = false
    @State private var showingQuickButtonSettings = false
    @State private var showingHooksAlert = false
    @State private var hooksAlertMessage = ""

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                // Server status
                HStack {
                    Circle()
                        .fill(serverManager.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    if serverManager.isRunning {
                        Text(serverManager.serverURL)
                            .font(.system(.title3, design: .monospaced))

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(serverManager.serverURL, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy URL")
                    } else {
                        Text("Server stopped")
                            .font(.title3)
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
                }

                if serverManager.isRunning {
                    HStack {
                        Text("PIN: \(serverManager.pin)")
                            .font(.system(.body, design: .monospaced))

                        Spacer()

                        Text("\(serverManager.connectedClients) connected")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Settings (only when stopped)
                if !serverManager.isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("PIN Authentication", isOn: $serverManager.pinEnabled)
                            Spacer()
                        }

                        HStack {
                            Text("Proxy Ports")
                            Spacer()
                            Text("\(serverManager.proxyPorts.count) configured")
                                .foregroundColor(.secondary)
                            Button("Edit") {
                                showingProxySettings = true
                            }
                        }

                        HStack {
                            Text("Quick Buttons")
                            Spacer()
                            Text("\(serverManager.quickButtons.count) configured")
                                .foregroundColor(.secondary)
                            Button("Edit") {
                                showingQuickButtonSettings = true
                            }
                        }

                        HStack {
                            Text("Claude Code Hooks")
                            Spacer()
                            if serverManager.isHooksInstalled {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Installed")
                                    .foregroundColor(.secondary)
                                Button("Uninstall") {
                                    let result = serverManager.uninstallHooks()
                                    hooksAlertMessage = result.message
                                    showingHooksAlert = true
                                }
                            } else {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                Text("Not installed")
                                    .foregroundColor(.secondary)
                                Button("Install") {
                                    let result = serverManager.installHooks()
                                    hooksAlertMessage = result.message
                                    showingHooksAlert = true
                                }
                            }
                        }
                    }
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()

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
        .frame(minWidth: 400, minHeight: 250)
        .alert("Hooks", isPresented: $showingHooksAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(hooksAlertMessage)
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
