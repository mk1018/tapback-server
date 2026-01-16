import AppKit
import SwiftUI
import Vapor

class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

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

    func applicationDidBecomeActive(_: Notification) {
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct TapbackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
