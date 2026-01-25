import Foundation
import Vapor

struct QuickButton: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var command: String

    init(id: UUID = UUID(), label: String, command: String) {
        self.id = id
        self.label = label
        self.command = command
    }
}

// Claude Code session status
struct ClaudeStatus: Codable, Equatable {
    let sessionId: String
    let status: String // "starting", "processing", "idle", "waiting", "ended"
    let projectDir: String?
    let model: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status
        case projectDir = "project_dir"
        case model
        case timestamp
    }
}

// Actor for thread-safe status storage
actor ClaudeStatusStore {
    // Key by project_dir instead of session_id
    private var statuses: [String: ClaudeStatus] = [:]

    func update(_ status: ClaudeStatus) {
        // Use project_dir as key if available, otherwise session_id
        let key = status.projectDir ?? status.sessionId
        statuses[key] = status
        // Clean up old sessions (older than 1 hour)
        let cutoff = Date().addingTimeInterval(-3600)
        statuses = statuses.filter { $0.value.timestamp > cutoff }
    }

    func getAll() -> [ClaudeStatus] {
        Array(statuses.values).sorted { $0.timestamp > $1.timestamp }
    }

    func get(projectDir: String) -> ClaudeStatus? {
        statuses[projectDir]
    }
}

@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 9876
    @Published var proxyPorts: [Int: Int] = [:] {
        didSet {
            if !isLoading { saveSettings() }
        }
    }

    @Published var pinEnabled: Bool = true {
        didSet {
            if !isLoading { saveSettings() }
        }
    }

    @Published var quickButtons: [QuickButton] = [] {
        didSet {
            if !isLoading { saveSettings() }
        }
    }

    @Published var pin: String = ""
    @Published var connectedClients = 0

    private var app: Application?
    private var proxyServers: [Int: Application] = [:]
    private var serverTask: Task<Void, Never>?
    private var proxyServerTasks: [Int: Task<Void, Never>] = [:]
    private var isLoading = false

    // Claude Code status management
    let claudeStatusStore = ClaudeStatusStore()
    private var wsConnections: [WebSocket] = []
    private let wsLock = NSLock()

    init() {
        loadSettings()
    }

    // MARK: - Claude Code Hooks Installation

    var isHooksInstalled: Bool {
        let hookPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks/tapback-status-hook.sh")
        return FileManager.default.fileExists(atPath: hookPath.path)
    }

    func installHooks() -> (success: Bool, message: String) {
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser
        let claudeDir = homeDir.appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let hookScriptPath = hooksDir.appendingPathComponent("tapback-status-hook.sh")
        let settingsPath = claudeDir.appendingPathComponent("settings.json")

        // Create hooks directory if needed
        do {
            try fm.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        } catch {
            return (false, "Failed to create hooks directory: \(error.localizedDescription)")
        }

        // Write hook script
        let hookScript = """
        #!/bin/bash
        # Tapback Status Hook for Claude Code
        # Auto-installed by Tapback

        set -e

        input=$(cat)

        hook_event_name=$(echo "$input" | jq -r '.hook_event_name // empty')
        session_id=$(echo "$input" | jq -r '.session_id // empty')
        cwd=$(echo "$input" | jq -r '.cwd // empty')
        model=$(echo "$input" | jq -r '.model // empty')

        if [ -z "$session_id" ]; then
            exit 0
        fi

        case "$hook_event_name" in
            "SessionStart") status="starting" ;;
            "UserPromptSubmit") status="processing" ;;
            "Stop") status="idle" ;;
            "Notification")
                notification_type=$(echo "$input" | jq -r '.notification_type // empty')
                if [ "$notification_type" = "idle_prompt" ]; then
                    status="waiting"
                else
                    exit 0
                fi
                ;;
            "SessionEnd") status="ended" ;;
            *) exit 0 ;;
        esac

        TAPBACK_URL="${TAPBACK_URL:-http://localhost:9876}"

        curl -s -X POST "${TAPBACK_URL}/api/claude-status" \\
            -H "Content-Type: application/json" \\
            -d "{\\"session_id\\":\\"$session_id\\",\\"status\\":\\"$status\\",\\"project_dir\\":\\"$cwd\\",\\"model\\":\\"$model\\"}" \\
            >/dev/null 2>&1 || true

        exit 0
        """

        do {
            try hookScript.write(to: hookScriptPath, atomically: true, encoding: .utf8)
            // Make executable
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath.path)
        } catch {
            return (false, "Failed to write hook script: \(error.localizedDescription)")
        }

        // Update settings.json
        let hookCommand = hookScriptPath.path
        let hooksConfig: [String: Any] = [
            "SessionStart": [["hooks": [["type": "command", "command": hookCommand]]]],
            "UserPromptSubmit": [["hooks": [["type": "command", "command": hookCommand]]]],
            "Stop": [["hooks": [["type": "command", "command": hookCommand]]]],
            "Notification": [["matcher": "idle_prompt", "hooks": [["type": "command", "command": hookCommand]]]],
            "SessionEnd": [["hooks": [["type": "command", "command": hookCommand]]]],
        ]

        var settings: [String: Any] = [:]

        // Read existing settings
        if let data = try? Data(contentsOf: settingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = existing
        }

        // Merge hooks (append to existing, don't overwrite)
        if var existingHooks = settings["hooks"] as? [String: Any] {
            for (key, value) in hooksConfig {
                if var existingArray = existingHooks[key] as? [[String: Any]],
                   let newArray = value as? [[String: Any]]
                {
                    // Check if Tapback hook already exists
                    let hasTapbackHook = existingArray.contains { item in
                        guard let hooks = item["hooks"] as? [[String: Any]] else { return false }
                        return hooks.contains { ($0["command"] as? String)?.contains("tapback-status-hook.sh") == true }
                    }
                    if !hasTapbackHook {
                        existingArray.append(contentsOf: newArray)
                    }
                    existingHooks[key] = existingArray
                } else {
                    existingHooks[key] = value
                }
            }
            settings["hooks"] = existingHooks
        } else {
            settings["hooks"] = hooksConfig
        }

        // Write settings
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsPath)
        } catch {
            return (false, "Failed to update settings.json: \(error.localizedDescription)")
        }

        return (true, "Hooks installed successfully. Restart Claude Code to apply.")
    }

    func uninstallHooks() -> (success: Bool, message: String) {
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser
        let claudeDir = homeDir.appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let hookScriptPath = hooksDir.appendingPathComponent("tapback-status-hook.sh")
        let settingsPath = claudeDir.appendingPathComponent("settings.json")

        // Remove hook script
        if fm.fileExists(atPath: hookScriptPath.path) {
            do {
                try fm.removeItem(at: hookScriptPath)
            } catch {
                return (false, "Failed to remove hook script: \(error.localizedDescription)")
            }
        }

        // Remove hooks from settings.json
        if let data = try? Data(contentsOf: settingsPath),
           var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = settings["hooks"] as? [String: Any]
        {
            // Remove Tapback hooks
            for key in ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "SessionEnd"] {
                if let hookArray = hooks[key] as? [[String: Any]] {
                    let filtered = hookArray.filter { item in
                        guard let innerHooks = item["hooks"] as? [[String: Any]] else { return true }
                        return !innerHooks.contains { h in
                            (h["command"] as? String)?.contains("tapback-status-hook.sh") == true
                        }
                    }
                    if filtered.isEmpty {
                        hooks.removeValue(forKey: key)
                    } else {
                        hooks[key] = filtered
                    }
                }
            }

            settings["hooks"] = hooks.isEmpty ? nil : hooks

            if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: settingsPath)
            }
        }

        return (true, "Hooks uninstalled successfully.")
    }

    private func saveSettings() {
        UserDefaults.standard.set(pinEnabled, forKey: "tapback_pinEnabled")
        if let data = try? JSONEncoder().encode(proxyPorts) {
            UserDefaults.standard.set(data, forKey: "tapback_proxyPorts")
        }
        if let data = try? JSONEncoder().encode(quickButtons) {
            UserDefaults.standard.set(data, forKey: "tapback_quickButtons")
        }
    }

    private func loadSettings() {
        isLoading = true
        if UserDefaults.standard.object(forKey: "tapback_pinEnabled") != nil {
            pinEnabled = UserDefaults.standard.bool(forKey: "tapback_pinEnabled")
        }
        if let data = UserDefaults.standard.data(forKey: "tapback_proxyPorts"),
           let saved = try? JSONDecoder().decode([Int: Int].self, from: data)
        {
            proxyPorts = saved
        }
        if let data = UserDefaults.standard.data(forKey: "tapback_quickButtons"),
           let saved = try? JSONDecoder().decode([QuickButton].self, from: data)
        {
            quickButtons = saved
        }
        isLoading = false
    }

    var serverURL: String {
        let ip = getLocalIP()
        return "http://\(ip):\(port)/"
    }

    var appURL: String? {
        guard let firstEntry = proxyPorts.min(by: { $0.key < $1.key }) else { return nil }
        let ip = getLocalIP()
        return "http://\(ip):\(firstEntry.value)/"
    }

    var localIP: String {
        getLocalIP()
    }

    func start() {
        guard !isRunning else { return }

        pin = String(format: "%04d", Int.random(in: 0 ... 9999))
        let currentPort = port
        let currentProxyPorts = proxyPorts
        let currentPinEnabled = pinEnabled
        let currentQuickButtons = quickButtons
        let authToken = UUID().uuidString
        let macIP = getLocalIP()

        // First proxy port for app URL (if any)
        let firstExternalPort = currentProxyPorts.min(by: { $0.key < $1.key })?.value

        // Start Terminal UI server
        serverTask = Task.detached { [weak self] in
            guard let self else { return }

            do {
                let app = try await Application.make(.production)
                app.http.server.configuration.port = currentPort
                app.http.server.configuration.hostname = "0.0.0.0"

                await configureTerminalRoutes(
                    app: app,
                    authToken: authToken,
                    macIP: macIP,
                    appPort: firstExternalPort,
                    pinEnabled: currentPinEnabled,
                    quickButtons: currentQuickButtons
                )

                await MainActor.run {
                    self.app = app
                    self.isRunning = true
                }

                try await app.execute()
            } catch {
                print("Terminal server error: \(error)")
                await MainActor.run {
                    self.isRunning = false
                }
            }
        }

        // Start proxy servers for each configured port
        for (targetPort, externalPort) in currentProxyPorts {
            print("[Tapback] Starting proxy server on port \(externalPort) -> localhost:\(targetPort)")
            let task = Task.detached { [weak self] in
                guard let self else { return }

                do {
                    let proxyServer = try await Application.make(.production)
                    proxyServer.http.server.configuration.port = externalPort
                    proxyServer.http.server.configuration.hostname = "0.0.0.0"
                    proxyServer.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(30))

                    await configureAppRoutes(
                        app: proxyServer,
                        targetPort: targetPort,
                        macIP: macIP,
                        appPort: externalPort,
                        allProxyPorts: currentProxyPorts
                    )

                    await MainActor.run {
                        self.proxyServers[targetPort] = proxyServer
                    }

                    print("[Tapback] Proxy server started: port \(externalPort) -> localhost:\(targetPort)")
                    try await proxyServer.execute()
                } catch {
                    print("[Tapback] Proxy server error (port \(externalPort)): \(error)")
                }
            }
            proxyServerTasks[targetPort] = task
        }

        if currentProxyPorts.isEmpty {
            print("[Tapback] No proxy ports configured")
        }
    }

    func stop() {
        serverTask?.cancel()

        for task in proxyServerTasks.values {
            task.cancel()
        }

        if let app {
            Task.detached {
                try? await app.asyncShutdown()
            }
        }

        for proxyServer in proxyServers.values {
            Task.detached {
                try? await proxyServer.asyncShutdown()
            }
        }

        app = nil
        proxyServers.removeAll()
        proxyServerTasks.removeAll()
        isRunning = false
        connectedClients = 0
    }

    // MARK: - Terminal UI Routes

    private func configureTerminalRoutes(
        app: Application,
        authToken: String,
        macIP: String,
        appPort: Int?,
        pinEnabled: Bool,
        quickButtons: [QuickButton]
    ) async {
        let pin = pin
        let appURL = appPort.map { "http://\(macIP):\($0)/" }

        // Terminal UI (root)
        app.get { req async -> Response in
            if pinEnabled {
                guard req.cookies["tapback_auth"]?.string == authToken else {
                    let response = Response(status: .seeOther)
                    response.headers.add(name: .location, value: "/auth")
                    return response
                }
            }

            let html = HTMLTemplates.mainPage(appURL: appURL, quickButtons: quickButtons)
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/html"],
                body: .init(string: html)
            )
        }

        // PIN auth page
        app.get("auth") { req -> Response in
            if !pinEnabled {
                let response = Response(status: .seeOther)
                response.headers.add(name: .location, value: "/")
                return response
            }

            if req.cookies["tapback_auth"]?.string == authToken {
                let response = Response(status: .seeOther)
                response.headers.add(name: .location, value: "/")
                return response
            }

            let html = HTMLTemplates.pinPage(error: nil)
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/html"],
                body: .init(string: html)
            )
        }

        app.post("auth") { req -> Response in
            struct PinRequest: Content {
                let pin: String
            }

            if !pinEnabled {
                let response = Response(status: .seeOther)
                response.headers.add(name: .location, value: "/")
                return response
            }

            guard let pinReq = try? req.content.decode(PinRequest.self),
                  pinReq.pin == pin
            else {
                let html = HTMLTemplates.pinPage(error: "Invalid PIN")
                return Response(
                    status: .unauthorized,
                    headers: ["Content-Type": "text/html"],
                    body: .init(string: html)
                )
            }

            let response = Response(status: .seeOther)
            response.headers.add(name: .location, value: "/")
            response.cookies["tapback_auth"] = HTTPCookies.Value(
                string: authToken,
                expires: Date().addingTimeInterval(86400),
                isHTTPOnly: true
            )
            return response
        }

        // API endpoint to list all tmux sessions
        app.get("api", "sessions") { _ async -> Response in
            let sessions = await TmuxHelper.listSessions()
            let json = sessions.map { "{\"name\":\"\($0)\"}" }.joined(separator: ",")
            return Response(
                status: .ok,
                headers: ["Content-Type": "application/json"],
                body: .init(string: "[\(json)]")
            )
        }

        // API endpoint to receive Claude Code status from hooks
        app.post("api", "claude-status") { [weak self] req async -> Response in
            guard let self else {
                return Response(status: .internalServerError)
            }

            struct StatusRequest: Content {
                let session_id: String
                let status: String
                let project_dir: String?
                let model: String?
            }

            guard let statusReq = try? req.content.decode(StatusRequest.self) else {
                return Response(status: .badRequest, body: .init(string: "Invalid request"))
            }

            let status = ClaudeStatus(
                sessionId: statusReq.session_id,
                status: statusReq.status,
                projectDir: statusReq.project_dir,
                model: statusReq.model,
                timestamp: Date()
            )

            await self.broadcastStatus(status)

            return Response(
                status: .ok,
                headers: ["Content-Type": "application/json"],
                body: .init(string: "{\"ok\":true}")
            )
        }

        // API endpoint to get all Claude Code statuses
        app.get("api", "claude-status") { [weak self] _ async -> Response in
            guard let self else {
                return Response(status: .internalServerError)
            }

            let statuses = await self.claudeStatusStore.getAll()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(statuses),
                  let json = String(data: data, encoding: .utf8)
            else {
                return Response(status: .internalServerError)
            }

            return Response(
                status: .ok,
                headers: ["Content-Type": "application/json"],
                body: .init(string: json)
            )
        }

        // WebSocket endpoint for terminal
        app.webSocket("ws") { [weak self] _, ws async in
            guard let self else { return }

            await MainActor.run {
                self.connectedClients += 1
            }
            self.addWebSocket(ws)

            // Send initial output for all tmux sessions
            let tmuxSessions = await TmuxHelper.listSessions()
            for sessionName in tmuxSessions {
                let output = await TmuxHelper.capture(session: sessionName)
                let path = await TmuxHelper.getCurrentPath(session: sessionName) ?? ""
                try? await ws.send("""
                {"t":"o","id":"\(sessionName)","c":"\(output.escaped)","path":"\(path.escaped)"}
                """)
            }

            // Send initial Claude Code statuses
            let statuses = await self.claudeStatusStore.getAll()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            for status in statuses {
                if let data = try? encoder.encode(status),
                   let jsonString = String(data: data, encoding: .utf8)
                {
                    try? await ws.send("{\"t\":\"status\",\"d\":\(jsonString)}")
                }
            }

            ws.onText { _, text async in
                guard let data = text.data(using: .utf8),
                      let msg = try? JSONDecoder().decode(WSMessage.self, from: data)
                else {
                    return
                }

                // Handle input - id is now tmux session name directly
                if msg.t == "i", let sessionName = msg.id, !sessionName.isEmpty {
                    await TmuxHelper.sendKeys(session: sessionName, text: msg.c ?? "")
                }
            }

            while !ws.isClosed {
                let currentSessions = await TmuxHelper.listSessions()
                for sessionName in currentSessions {
                    let output = await TmuxHelper.capture(session: sessionName)
                    let path = await TmuxHelper.getCurrentPath(session: sessionName) ?? ""
                    try? await ws.send("""
                    {"t":"o","id":"\(sessionName)","c":"\(output.escaped)","path":"\(path.escaped)"}
                    """)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            self.removeWebSocket(ws)
            await MainActor.run {
                self.connectedClients -= 1
            }
        }
    }

    // MARK: - Web App Proxy Routes (ngrok-style)

    private func configureAppRoutes(
        app: Application,
        targetPort: Int,
        macIP: String,
        appPort: Int,
        allProxyPorts: [Int: Int]
    ) async {
        // All requests proxy to localhost:targetPort
        app.get { req async -> Response in
            await self.proxyToLocalhost(req: req, path: "/", method: "GET", targetPort: targetPort, macIP: macIP, appPort: appPort, allProxyPorts: allProxyPorts)
        }

        app.get("**") { req async -> Response in
            await self.proxyToLocalhost(req: req, path: req.url.path, method: "GET", targetPort: targetPort, macIP: macIP, appPort: appPort, allProxyPorts: allProxyPorts)
        }

        app.post("**") { req async -> Response in
            await self.proxyToLocalhost(req: req, path: req.url.path, method: "POST", targetPort: targetPort, macIP: macIP, appPort: appPort, allProxyPorts: allProxyPorts)
        }

        app.put("**") { req async -> Response in
            await self.proxyToLocalhost(req: req, path: req.url.path, method: "PUT", targetPort: targetPort, macIP: macIP, appPort: appPort, allProxyPorts: allProxyPorts)
        }

        app.delete("**") { req async -> Response in
            await self.proxyToLocalhost(req: req, path: req.url.path, method: "DELETE", targetPort: targetPort, macIP: macIP, appPort: appPort, allProxyPorts: allProxyPorts)
        }

        app.patch("**") { req async -> Response in
            await self.proxyToLocalhost(req: req, path: req.url.path, method: "PATCH", targetPort: targetPort, macIP: macIP, appPort: appPort, allProxyPorts: allProxyPorts)
        }

        app.on(.OPTIONS, "**") { req async -> Response in
            await self.proxyToLocalhost(req: req, path: req.url.path, method: "OPTIONS", targetPort: targetPort, macIP: macIP, appPort: appPort, allProxyPorts: allProxyPorts)
        }
    }

    private func proxyToLocalhost(req: Request, path: String, method: String, targetPort: Int, macIP: String, appPort _: Int, allProxyPorts: [Int: Int]) async -> Response {
        let query = req.url.query.map { "?\($0)" } ?? ""
        let targetURL = "http://127.0.0.1:\(targetPort)\(path)\(query)"

        let contentType = req.headers.first(name: "Content-Type") ?? "none"
        print("[Tapback] Proxying \(method) \(path) -> \(targetURL) [Content-Type: \(contentType)]")

        guard let url = URL(string: targetURL) else {
            return Response(status: .badRequest, body: .init(string: "Invalid URL"))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 30

        for (name, value) in req.headers {
            let lowerName = name.lowercased()
            if lowerName != "host", lowerName != "connection", lowerName != "accept-encoding", lowerName != "transfer-encoding", lowerName != "origin", lowerName != "referer" {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
        }
        urlRequest.setValue("localhost:\(targetPort)", forHTTPHeaderField: "Host")
        urlRequest.setValue("http://localhost:\(targetPort)", forHTTPHeaderField: "Origin")
        urlRequest.setValue("http://localhost:\(targetPort)/", forHTTPHeaderField: "Referer")
        urlRequest.setValue(macIP, forHTTPHeaderField: "X-Forwarded-Host")
        urlRequest.setValue("http", forHTTPHeaderField: "X-Forwarded-Proto")
        if let clientIP = req.headers.first(name: "X-Forwarded-For") {
            urlRequest.setValue(clientIP, forHTTPHeaderField: "X-Forwarded-For")
        } else if let remoteAddress = req.remoteAddress?.ipAddress {
            urlRequest.setValue(remoteAddress, forHTTPHeaderField: "X-Forwarded-For")
        }

        if let body = req.body.data {
            urlRequest.httpBody = Data(buffer: body)
            print("[Tapback] Request body (cached): \(body.readableBytes) bytes")
        } else if let collected = try? await req.body.collect().get() {
            urlRequest.httpBody = Data(buffer: collected)
            print("[Tapback] Request body (collected): \(collected.readableBytes) bytes")
        } else {
            print("[Tapback] Request body: none")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return Response(status: .badGateway, body: .init(string: "Invalid response"))
            }

            var headers = HTTPHeaders()
            var contentType: String?

            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    let lowerKey = keyString.lowercased()
                    if lowerKey != "transfer-encoding", lowerKey != "connection", lowerKey != "keep-alive", lowerKey != "content-encoding" {
                        headers.add(name: keyString, value: valueString)
                        if lowerKey == "content-type" {
                            contentType = valueString
                        }
                    }
                }
            }

            var responseData = data
            if let ct = contentType, isTextContent(contentType: ct) {
                if var text = String(data: data, encoding: .utf8) {
                    text = rewriteLocalhost(in: text, macIP: macIP, allProxyPorts: allProxyPorts)
                    if let rewritten = text.data(using: .utf8) {
                        responseData = rewritten
                    }
                }
            }

            headers.replaceOrAdd(name: "Content-Length", value: String(responseData.count))

            print("[Tapback] Proxy success: \(httpResponse.statusCode), \(responseData.count) bytes")
            return Response(
                status: HTTPResponseStatus(statusCode: httpResponse.statusCode),
                headers: headers,
                body: .init(data: responseData)
            )
        } catch {
            print("[Tapback] Proxy error: \(error)")
            let errorHTML = """
            <!DOCTYPE html>
            <html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Proxy Error</title>
            <style>body{font-family:sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;align-items:center;justify-content:center;text-align:center;padding:20px}
            .e{color:#f85149;font-size:1.2rem;margin-bottom:1rem}.m{color:#8b949e;font-size:0.9rem}</style></head>
            <body><div><div class="e">localhost:\(targetPort) に接続できません</div><div class="m">\(error.localizedDescription)</div></div></body></html>
            """
            return Response(
                status: .badGateway,
                headers: ["Content-Type": "text/html"],
                body: .init(string: errorHTML)
            )
        }
    }

    private func isTextContent(contentType: String) -> Bool {
        let ct = contentType.lowercased()
        return ct.contains("text/") ||
            ct.contains("application/javascript") ||
            ct.contains("application/json") ||
            ct.contains("application/xml") ||
            ct.contains("application/xhtml") ||
            ct.contains("+json") ||
            ct.contains("+xml")
    }

    private func rewriteLocalhost(in text: String, macIP: String, allProxyPorts: [Int: Int]) -> String {
        var result = text

        for (targetPort, externalPort) in allProxyPorts {
            let replacements = [
                ("http://localhost:\(targetPort)", "http://\(macIP):\(externalPort)"),
                ("https://localhost:\(targetPort)", "https://\(macIP):\(externalPort)"),
                ("http://127.0.0.1:\(targetPort)", "http://\(macIP):\(externalPort)"),
                ("https://127.0.0.1:\(targetPort)", "https://\(macIP):\(externalPort)"),
                ("//localhost:\(targetPort)", "//\(macIP):\(externalPort)"),
                ("//127.0.0.1:\(targetPort)", "//\(macIP):\(externalPort)"),
                ("'localhost:\(targetPort)", "'\(macIP):\(externalPort)"),
                ("\"localhost:\(targetPort)", "\"\(macIP):\(externalPort)"),
                ("'127.0.0.1:\(targetPort)", "'\(macIP):\(externalPort)"),
                ("\"127.0.0.1:\(targetPort)", "\"\(macIP):\(externalPort)"),
                ("`localhost:\(targetPort)", "`\(macIP):\(externalPort)"),
                ("`127.0.0.1:\(targetPort)", "`\(macIP):\(externalPort)"),
            ]

            for (from, to) in replacements {
                result = result.replacingOccurrences(of: from, with: to)
            }
        }

        return result
    }

    // WebSocket connection management for status broadcasts
    private func addWebSocket(_ ws: WebSocket) {
        wsLock.lock()
        wsConnections.append(ws)
        wsLock.unlock()
    }

    private func removeWebSocket(_ ws: WebSocket) {
        wsLock.lock()
        wsConnections.removeAll { $0 === ws }
        wsLock.unlock()
    }

    func broadcastStatus(_ status: ClaudeStatus) async {
        await claudeStatusStore.update(status)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(status),
              let jsonString = String(data: data, encoding: .utf8)
        else { return }

        let message = "{\"t\":\"status\",\"d\":\(jsonString)}"

        wsLock.lock()
        let connections = wsConnections
        wsLock.unlock()

        for ws in connections {
            if !ws.isClosed {
                try? await ws.send(message)
            }
        }
    }

    private func getLocalIP() -> String {
        var address = "127.0.0.1"

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return address
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee

            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }

        return address
    }
}

struct WSMessage: Codable {
    let t: String
    let id: String?
    let c: String?
}

extension String {
    var escaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
