import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_: Notification) {
        // Set app icon
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL)
        {
            NSApp.applicationIconImage = icon
        }

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
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(serverManager)
        } label: {
            Image(systemName: serverManager.isRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
        }
        .menuBarExtraStyle(.menu)

        Window("Tapback", id: "main") {
            ContentView()
                .environmentObject(serverManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        if serverManager.isRunning {
            Text(serverManager.serverURL)
            Text("PIN: \(serverManager.pin)")
            Divider()
            Button("Stop Server") {
                serverManager.stop()
            }
        } else {
            Button("Start Server") {
                serverManager.start()
            }
        }

        Divider()

        Button("Open Window") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
