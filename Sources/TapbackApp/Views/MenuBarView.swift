import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var serverManager: ServerManager
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Window") {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    for window in NSApp.windows where window.title == "Tapback" {
                        window.level = .floating
                        window.makeKeyAndOrderFront(nil)
                        window.level = .normal
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 120)
    }
}
