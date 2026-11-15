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
        .commands {
            CommandGroup(after: .importExport) {
                ExportCueListCommand(model: model, qlab: model.qlab, settings: model.settings)
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
