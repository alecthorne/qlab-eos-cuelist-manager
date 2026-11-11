import AppKit
import SwiftUI

@main
struct QLabEosCuelistManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("QLab → Eos CueSync") {
            ContentView()
                .environmentObjects(model)
                .frame(minWidth: 900, minHeight: 520)
        }
        Settings {
            SettingsView()
                .environmentObjects(model)
                .frame(width: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when running straight from Swift Package Manager, which builds a bare
        // executable rather than an .app bundle: give it a Dock icon and bring it forward.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension View {
    /// Injects the model and each object it owns, so views can observe them directly.
    func environmentObjects(_ model: AppModel) -> some View {
        self
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.log)
            .environmentObject(model.interfaces)
            .environmentObject(model.qlab)
            .environmentObject(model.eos)
            .environmentObject(model.actionLog)
            .environmentObject(model.changes)
    }
}
