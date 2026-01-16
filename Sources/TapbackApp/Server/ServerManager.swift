import Foundation
import Vapor

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

    @Published var pin: String = ""
    @Published var connectedClients = 0

    private var app: Application?
    private var proxyServers: [Int: Application] = [:]
    private var serverTask: Task<Void, Never>?
    private var proxyServerTasks: [Int: Task<Void, Never>] = [:]
    private var isLoading = false

    init() {
        loadSettings()
    }

    private func saveSettings() {
        UserDefaults.standard.set(pinEnabled, forKey: "tapback_pinEnabled")
        if let data = try? JSONEncoder().encode(proxyPorts) {
            UserDefaults.standard.set(data, forKey: "tapback_proxyPorts")
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

    func start(sessionManager: SessionManager) {
        guard !isRunning else { return }

        pin = String(format: "%04d", Int.random(in: 0 ... 9999))
        let currentPort = port
        let currentProxyPorts = proxyPorts
        let currentPinEnabled = pinEnabled
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
                    sessionManager: sessionManager,
                    authToken: authToken,
                    macIP: macIP,
                    appPort: firstExternalPort,
                    pinEnabled: currentPinEnabled
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
        sessionManager: SessionManager,
        authToken: String,
        macIP: String,
        appPort: Int?,
        pinEnabled: Bool
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

            let html = await HTMLTemplates.mainPage(sessions: sessionManager.sessions, appURL: appURL)
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

        // WebSocket endpoint for terminal
        app.webSocket("ws") { _, ws async in
            await MainActor.run {
                self.connectedClients += 1
            }

            for session in await sessionManager.sessions where session.isActive {
                let output = await sessionManager.getOutput(for: session.id)
                try? await ws.send("""
                {"t":"o","id":"\(session.id.uuidString)","c":"\(output.escaped)"}
                """)
            }

            ws.onText { _, text async in
                guard let data = text.data(using: .utf8),
                      let msg = try? JSONDecoder().decode(WSMessage.self, from: data)
                else {
                    return
                }

                if msg.t == "i", let sessionId = UUID(uuidString: msg.id ?? "") {
                    await sessionManager.sendInput(msg.c ?? "", to: sessionId)
                }
            }

            while !ws.isClosed {
                for session in await sessionManager.sessions where session.isActive {
                    let output = await sessionManager.getOutput(for: session.id)
                    try? await ws.send("""
                    {"t":"o","id":"\(session.id.uuidString)","c":"\(output.escaped)"}
                    """)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

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
