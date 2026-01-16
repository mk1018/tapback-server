import SwiftUI
import Vapor

@main
struct TapbackApp: App {
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(serverManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}
