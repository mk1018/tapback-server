import Foundation
import Vapor

@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 8080
    @Published var pin: String = ""
    @Published var connectedClients = 0

    private var app: Application?
    private var serverTask: Task<Void, Never>?

    var serverURL: String {
        let ip = getLocalIP()
        return "http://\(ip):\(port)"
    }

    func start(sessionManager: SessionManager) {
        guard !isRunning else { return }

        pin = String(format: "%04d", Int.random(in: 0...9999))

        serverTask = Task.detached { [weak self] in
            guard let self = self else { return }

            do {
                var env = Environment.production
                env.arguments = ["serve", "--port", "\(await self.port)"]

                let app = try await Application.make(env)

                // Configure routes
                await self.configureRoutes(app: app, sessionManager: sessionManager)

                await MainActor.run {
                    self.app = app
                    self.isRunning = true
                }

                try await app.execute()
            } catch {
                print("Server error: \(error)")
                await MainActor.run {
                    self.isRunning = false
                }
            }
        }
    }

    func stop() {
        serverTask?.cancel()
        app?.shutdown()
        app = nil
        isRunning = false
        connectedClients = 0
    }

    private func configureRoutes(app: Application, sessionManager: SessionManager) async {
        let pin = self.pin

        // Serve main page
        app.get { req async -> Response in
            let html = await HTMLTemplates.mainPage(sessions: sessionManager.sessions)
            return Response(
                status: .ok,
                headers: ["Content-Type": "text/html"],
                body: .init(string: html)
            )
        }

        // PIN auth page
        app.get("auth") { req -> Response in
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

            guard let pinReq = try? req.content.decode(PinRequest.self),
                  pinReq.pin == pin else {
                let html = HTMLTemplates.pinPage(error: "Invalid PIN")
                return Response(
                    status: .unauthorized,
                    headers: ["Content-Type": "text/html"],
                    body: .init(string: html)
                )
            }

            // Set auth cookie and redirect
            let response = Response(status: .seeOther)
            response.headers.add(name: .location, value: "/")
            response.cookies["tapback_auth"] = HTTPCookies.Value(
                string: UUID().uuidString,
                expires: Date().addingTimeInterval(86400),
                isHTTPOnly: true
            )
            return response
        }

        // WebSocket endpoint
        app.webSocket("ws") { req, ws async in
            await MainActor.run {
                self.connectedClients += 1
            }

            // Send initial output
            for session in await sessionManager.sessions where session.isActive {
                let output = await sessionManager.getOutput(for: session.id)
                try? await ws.send("""
                    {"t":"o","id":"\(session.id.uuidString)","c":"\(output.escaped)"}
                    """)
            }

            // Handle incoming messages
            ws.onText { ws, text async in
                guard let data = text.data(using: .utf8),
                      let msg = try? JSONDecoder().decode(WSMessage.self, from: data) else {
                    return
                }

                if msg.t == "i", let sessionId = UUID(uuidString: msg.id ?? "") {
                    await sessionManager.sendInput(msg.c ?? "", to: sessionId)
                }
            }

            // Polling loop
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

    private func getLocalIP() -> String {
        var address: String = "127.0.0.1"

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
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
