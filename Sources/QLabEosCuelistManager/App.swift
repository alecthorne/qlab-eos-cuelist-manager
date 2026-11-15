import AppKit
import SwiftUI

@main
struct QLabEosCuelistManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("QLab → Eos CueSync", id: MainWindowCommand.windowID) {
            ContentView()
                .environmentObjects(model)
                .frame(minWidth: 900, minHeight: 520)
        }
        .commands {
            CommandGroup(after: .importExport) {
                ExportCueListCommand(model: model, qlab: model.qlab, settings: model.settings)
            }
            CommandGroup(before: .windowList) {
                MainWindowCommand()
                Button("Active Eos Cues") {
                    ActiveCuesWindowController.shared.show(model: model)
                }
                .keyboardShortcut("1")
                Divider()
            }
            CommandGroup(replacing: .help) {
                HelpCommand()
            }
        }
        Window("QLab → Eos CueSync Help", id: HelpView.windowID) {
            HelpView()
                .frame(minWidth: 520, idealWidth: 720, minHeight: 400, idealHeight: 700)
        }
        .defaultSize(width: 720, height: 700)
        Settings {
            SettingsView()
                .environmentObjects(model)
                .frame(width: 560)
        }
    }
}

/// File → Export Cue List as PDF…. Observes QLab and Settings so it is only enabled once
/// there's a cue list to export.
private struct ExportCueListCommand: View {
    let model: AppModel
    @ObservedObject var qlab: QLabClient
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button("Export Cue List as PDF…") { CueListExport.run(model) }
            .keyboardShortcut("e")
            .disabled(!CueListExport.isAvailable(model))
    }
}

/// Window › Main Window (⌘0): brings the main window to the front, or reopens it if it was
/// closed (for example, leaving only the floating Active Eos Cues window open).
private struct MainWindowCommand: View {
    static let windowID = "main"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Main Window") {
            // SwiftUI names the group's windows "main-…"; reuse an open one rather than
            // opening a second.
            if let window = NSApp.windows.first(where: { window in
                window.identifier?.rawValue.hasPrefix(Self.windowID) == true
                    && (window.isVisible || window.isMiniaturized)
            }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: Self.windowID)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("0")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when running straight from Swift Package Manager, which builds a bare
        // executable rather than an .app bundle: give it a Dock icon and bring it forward.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Quits when the last window closes, except while the floating Active Eos Cues window is
    /// open: then the main window can be closed and the app keeps running. (Closing the
    /// floating window last quits the app; see ActiveCuesWindowController.)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !ActiveCuesWindowController.shared.isOpen
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
