import AppKit
import SwiftUI
import Vapor

class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_: Notification) {
        // Handle Ctrl+C using DispatchSource
        signal(SIGINT, SIG_IGN)
        sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource?.setEventHandler {
            NSApp.terminate(nil)
        }
        sigintSource?.resume()

        signal(SIGTERM, SIG_IGN)
        sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource?.setEventHandler {
            NSApp.terminate(nil)
        }
        sigtermSource?.resume()
    }
}

@main
struct TapbackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(sessionManager)
                .environmentObject(serverManager)
        } label: {
            Image(systemName: serverManager.isRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
        }
        .menuBarExtraStyle(.window)

        Window("Tapback", id: "main") {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(serverManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}
