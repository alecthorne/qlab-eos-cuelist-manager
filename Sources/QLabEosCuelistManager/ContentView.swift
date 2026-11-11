import AppKit
import CueSyncCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var eos: EosClient
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectionsHeader()
            Divider()
                .padding(.vertical, 6)

            if settings.eosCueList == nil {
                Banner(text: "Choose the Eos cue list to sync before anything else.",
                       buttonTitle: "Open Settings") { showingSettings = true }
            } else if settings.qlabCueListID.isEmpty {
                Banner(text: "Choose the QLab cue list to use as the source of truth.",
                       buttonTitle: "Open Settings") { showingSettings = true }
            }

            ComparisonPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            ActionLogSection()
            Divider()
            ConnectionLogSection()
        }
        .toolbar {
            ToolbarItem {
                ActiveCueBox()
            }
            .hidingSharedBackground()
            ToolbarItemGroup {
                Button {
                    qlab.refreshCueLists()
                    eos.refreshCues()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            VStack(spacing: 0) {
                SettingsView()
                    .environmentObjects(model)
                HStack {
                    Spacer()
                    Button("Done") { showingSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(width: 580, height: 720)
        }
        .background(NoInitialFocus())
        .onAppear {
            model.startIfNeeded()
            if settings.eosCueList == nil || settings.eosHost.isEmpty {
                showingSettings = true
            }
        }
    }
}

// MARK: - Connections

/// QLab and Eos connection details, side by side, at the top of the window.
struct ConnectionsHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connections").font(.headline)
                .padding(.horizontal, 12)
            HStack(alignment: .top, spacing: 0) {
                QLabConnectionColumn()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                Divider()
                EosConnectionColumn()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct QLabConnectionColumn: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ConnectionTitle(title: "QLab Connection", color: statusColor, detail: statusDetail)
            DetailLine(label: "Workspace:", value: qlab.connectedWorkspace?.displayName ?? "—")
            DetailLine(label: "Cue List:", value: cueList.text, isError: cueList.isError)
        }
    }

    private var cueList: (text: String, isError: Bool) {
        if settings.qlabCueListID.isEmpty { return ("None chosen in Settings", false) }
        if let list = model.selectedQLabCueList { return (list.displayName, false) }
        // The chosen list can only be looked for once a workspace is open.
        if qlab.status != .connected { return ("—", false) }
        return ("Cue list not found in workspace", true)
    }

    private var statusColor: Color {
        switch qlab.status {
        case .connected: return .green
        case .connecting, .waitingForWorkspace: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    /// Shown after the title when not connected, so the reason is visible.
    private var statusDetail: String? {
        switch qlab.status {
        case .connected: return nil
        case .connecting: return "Connecting…"
        case .waitingForWorkspace(let reason): return reason
        case .disconnected: return "Not connected"
        case .error(let reason): return reason
        }
    }
}

struct EosConnectionColumn: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ConnectionTitle(title: "Eos Connection", color: statusColor, detail: statusDetail)
                .help(eos.version.isEmpty ? "" : "Eos v\(eos.version)")
            DetailLine(label: "Showfile:", value: eos.showName.isEmpty ? "—" : eos.showName)
            DetailLine(label: "Video Cuelist:", value: videoCueList.text, isError: videoCueList.isError)
        }
    }

    private var videoCueList: (text: String, isError: Bool) {
        guard let number = settings.eosCueList else { return ("None chosen in Settings", false) }
        guard eos.status == .connected else { return ("\(number)", false) }
        guard let lists = eos.consoleCueLists else { return ("\(number) (checking…)", false) }
        guard let label = lists[number] else { return ("Cuelist not found in console", true) }
        return (label.isEmpty ? "\(number)" : "\(number) · \(label)", false)
    }

    private var statusColor: Color {
        switch eos.status {
        case .connected: return .green
        case .connecting, .notConfigured: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusDetail: String? {
        switch eos.status {
        case .connected: return nil
        case .connecting: return "Connecting…"
        case .notConfigured(let reason): return reason
        case .disconnected: return "Not connected"
        case .error(let reason): return reason
        }
    }
}

/// The Eos active cue, in a box in the window toolbar.
struct ActiveCueBox: View {
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        HStack(spacing: 6) {
            Text("Active Eos Cue (main cuelist):")
                .foregroundStyle(.secondary)
            Text(eos.activeCueText.isEmpty ? "None" : eos.activeCueText)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
        .help("The cue Eos is currently playing back")
    }
}

extension ToolbarContent {
    /// The box draws its own background, so don't also put it in the toolbar's shared
    /// glass background (macOS 26 and later).
    @ToolbarContentBuilder
    func hidingSharedBackground() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// "● QLab Connection", in bold, with the reason after it when not connected.
private struct ConnectionTitle: View {
    let title: String
    let color: Color
    let detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).bold()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detail)
            }
        }
    }
}

/// "Label: value" on one line; the value turns red for errors.
private struct DetailLine: View {
    let label: String
    let value: String
    var isError = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(isError ? Color.red : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(value)
        }
    }
}

/// One-line connection status, used in Settings.
struct StatusLabel: View {
    @ObservedObject var qlab: QLabClient

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).lineLimit(1)
        }
    }

    private var color: Color {
        switch qlab.status {
        case .connected: return .green
        case .connecting, .waitingForWorkspace: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var text: String {
        switch qlab.status {
        case .connected: return "QLab: \(qlab.connectedWorkspace?.displayName ?? "connected")"
        case .connecting: return "QLab: connecting…"
        case .waitingForWorkspace(let reason): return "QLab: \(reason)"
        case .disconnected: return "QLab: not connected"
        case .error(let reason): return "QLab: \(reason)"
        }
    }
}

struct EosStatusLabel: View {
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).lineLimit(1)
        }
    }

    private var color: Color {
        switch eos.status {
        case .connected: return .green
        case .connecting, .notConfigured: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var text: String {
        switch eos.status {
        case .connected:
            var parts = ["Eos: connected"]
            if !eos.version.isEmpty { parts.append("v\(eos.version)") }
            if !eos.showName.isEmpty { parts.append(eos.showName) }
            return parts.joined(separator: " · ")
        case .connecting: return "Eos: connecting…"
        case .notConfigured(let reason): return "Eos: \(reason)"
        case .disconnected: return "Eos: not connected"
        case .error(let reason): return "Eos: \(reason)"
        }
    }
}

/// Leaves nothing focused when the window first opens. Otherwise macOS focuses the first
/// control (the Action log's disclosure arrow). Tab still moves focus as usual afterwards.
private struct NoInitialFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClearsFocusOnce() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ClearsFocusOnce: NSView {
        private var cleared = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !cleared, let window else { return }
            cleared = true
            // Wait a turn so this runs after the window has chosen its initial focus.
            DispatchQueue.main.async { [weak window] in
                window?.makeFirstResponder(nil)
            }
        }
    }
}

struct Banner: View {
    let text: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
            Spacer()
            Button(buttonTitle, action: action)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }
}

// MARK: - Log

/// Connection events, newest first, in a panel at the bottom of the window.
/// Starts collapsed each time the app opens.
struct ConnectionLogSection: View {
    @EnvironmentObject private var log: ConnectionLog
    @State private var expanded = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if log.log.lines.isEmpty {
                Placeholder(text: "No connection events yet.")
                    .frame(height: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.log.lines.reversed()) { line in
                            Text("\(Self.timeFormatter.string(from: line.date))  [\(line.source)]  \(line.text)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 120)
            }
        } label: {
            HStack {
                Text("Connection Log")
                Spacer()
                if expanded {
                    Button("Clear") { log.clear() }
                        .buttonStyle(.borderless)
                        .disabled(log.log.lines.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
