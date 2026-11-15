import AppKit
import CueSyncCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var eos: EosClient
    @State private var showingSettings = false
    /// Where the Eos panel in the cue list starts, so the Eos connection details can line up
    /// with it. nil while the cue list isn't showing.
    @State private var eosPanelX: CGFloat?
    /// Where the Changes to Approve panel starts, so the Active Eos Cues panel above it can line
    /// up with it. nil while the cue list isn't showing.
    @State private var approvalPanelX: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            ConnectionsHeader(eosColumnX: eosPanelX, activeCueX: approvalPanelX)
            Divider()

            if eos.gaveUp {
                Banner(text: "Can't connect to Eos. Check the IP address and network connection in Settings.",
                       buttonTitle: "Open Settings") { showingSettings = true }
            }
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
            ToolbarItemGroup {
                Button {
                    CueListExport.run(model)
                } label: {
                    Label("Export Cue List as PDF", systemImage: "square.and.arrow.up")
                }
                .help("Export Cue List as PDF")
                .disabled(!CueListExport.isAvailable(model))
                Button {
                    qlab.refreshCueLists()
                    if eos.status == .connected {
                        eos.refreshCues()
                    } else {
                        // Starts over with a fresh set of retries, like Connect to Eos in Settings.
                        model.connectEos()
                    }
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
        .coordinateSpace(name: EosPanelXKey.coordinateSpace)
        .onPreferenceChange(EosPanelXKey.self) { eosPanelX = $0 }
        .onPreferenceChange(ApprovalPanelXKey.self) { approvalPanelX = $0 }
        .background(NoInitialFocus())
        .background(RemembersWindowFrame(name: "MainWindow"))
        .onAppear {
            model.startIfNeeded()
            if settings.eosCueList == nil || settings.eosHost.isEmpty {
                showingSettings = true
            }
        }
    }
}

// MARK: - Layout

/// Spacing shared by the main window's sections, so their edges and headings line up.
enum Layout {
    /// From the window edge (or a pane edge) to a section's content.
    static let edge: CGFloat = 16
    /// Above a section heading, so it reads as the start of a new section.
    static let headingTop: CGFloat = 14
    /// Below a section heading, so it groups with what follows.
    static let headingBottom: CGFloat = 6
    /// Between related rows in a section.
    static let rowGap: CGFloat = 8
    /// Between lines within a group, like a connection's details.
    static let tight: CGFloat = 4
    /// Below a section's last row, before the next divider.
    static let sectionBottom: CGFloat = 14
    /// Height of the controls row under the Cues and Changes to Approve headings, so the cue
    /// table and the change list start at the same height (buttons are taller than a checkbox).
    static let controlsRowHeight: CGFloat = 28
}

/// A section heading ("CONNECTIONS", "ACTIVE EOS CUES", "CUES", "CHANGES TO APPROVE") with the shared spacing.
struct SectionHeading: View {
    let title: String
    var top = Layout.headingTop

    init(_ title: String, top: CGFloat = Layout.headingTop) {
        self.title = title
        self.top = top
    }

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, top)
            .padding(.bottom, Layout.headingBottom)
    }
}

// MARK: - Connections

/// The left edge of the Eos panel in the cue list, in the main window's coordinates.
/// The Connections section reads it to line the Eos details up with the Eos cues below.
struct EosPanelXKey: PreferenceKey {
    static let coordinateSpace = "mainWindow"
    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// The left edge of the Changes to Approve panel, in the main window's coordinates.
/// The Active Eos Cues panel above it starts there too.
struct ApprovalPanelXKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// QLab and Eos connection details, side by side, at the top of the window, with the Eos
/// active cues to their right while Eos is connected.
struct ConnectionsHeader: View {
    /// Where the Eos panel below starts. When set, the Eos details start there too, with the
    /// dividing line above the gap before it; otherwise the two halves are equal.
    var eosColumnX: CGFloat?
    /// Where the Changes to Approve panel below starts. When set, the Active Eos Cues panel starts
    /// there too, so the two are the same width and resize together.
    var activeCueX: CGFloat?

    @EnvironmentObject private var eos: EosClient

    /// The Active Eos Cues panel's width when there's no Changes to Approve panel to line up with:
    /// the Changes to Approve panel's ideal width.
    private static let activeCueWidth: CGFloat = 360

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            connections
            if eos.status == .connected {
                ActiveCuesPanel()
                    .frame(width: activeCueX == nil ? Self.activeCueWidth : nil)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("CONNECTIONS")
                .padding(.horizontal, Layout.edge)
            HStack(alignment: .top, spacing: 0) {
                if let eosColumnX {
                    let halfGap = CueComparisonList.bandGap / 2
                    QLabConnectionColumn()
                        .padding(.leading, Layout.edge)
                        .padding(.trailing, halfGap)
                        .frame(width: max(eosColumnX - halfGap, 0), alignment: .leading)
                    Divider()
                    EosConnectionColumn()
                        .padding(.leading, halfGap)
                        .padding(.trailing, Layout.edge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    QLabConnectionColumn()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Layout.edge)
                    Divider()
                    EosConnectionColumn()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Layout.edge)
                }
            }
        }
        .padding(.bottom, Layout.sectionBottom)
        .frame(width: connectionsWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// nil (fill the window) without the Active Eos Cues panel. With it, ends where the panel starts.
    private var connectionsWidth: CGFloat? {
        guard eos.status == .connected, let activeCueX else { return nil }
        return max(activeCueX, 0)
    }
}

/// The active cue in the main and video cuelists, to the right of the connections, in a green
/// box (heading included) styled like the QLab and Eos panels in the cue list.
private struct ActiveCuesPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        // Clicking anywhere on the box opens the floating Active Eos Cues window.
        Button {
            ActiveCuesWindowController.shared.show(model: model)
        } label: {
            box
        }
        .buttonStyle(.plain)
        .help("Click to show the active cues in a floating window")
        .padding(.horizontal, Layout.edge)
        .padding(.vertical, Self.boxInset)
    }

    private var box: some View {
        VStack(spacing: 0) {
            // The box starts `boxInset` down, so this keeps the heading level with CONNECTIONS.
            SectionHeading("ACTIVE EOS CUES", top: Layout.headingTop - Self.boxInset)
            VStack(alignment: .leading, spacing: Layout.tight) {
                ActiveCueLine(label: "Main Cuelist:", value: ActiveCues.mainCueText(eos: eos))
                    .help("The cue Eos is currently playing back in the main cuelist, set in Settings")
                ActiveCueLine(label: "Video Cuelist:", value: ActiveCues.videoCueText(settings: settings, eos: eos))
                    .help("The cue Eos is currently playing back in the video cuelist being synced")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, Layout.rowGap)
        // Fills the panel, however tall the connections beside it are.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .activeCuesBox()
    }

    /// Space above and below the box, inside the panel.
    private static let boxInset = Layout.rowGap
}

/// "Main Cuelist: 1/5 - Lights up 3.0", with "None" when no cue is active.
private struct ActiveCueLine: View {
    let label: String
    let value: String

    var body: some View {
        // Larger than the rest of the window, since these are what the operator watches.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Text(value.isEmpty ? "None" : value)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.title3)
    }
}

struct QLabConnectionColumn: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.tight) {
            ConnectionTitle(title: "QLab", color: statusColor, detail: statusDetail)
            DetailLine(label: "Workspace:", value: qlab.connectedWorkspace?.displayName ?? "—")
            DetailLine(label: "Cue List:", value: cueList.text, isError: cueList.isError)
        }
    }

    private var cueList: (text: String, isError: Bool) {
        if settings.qlabCueListID.isEmpty { return ("None Chosen in Settings", false) }
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
        case .disconnected: return "Not Connected"
        case .error(let reason): return reason
        }
    }
}

struct EosConnectionColumn: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.tight) {
            ConnectionTitle(title: "Eos", color: statusColor, detail: statusDetail)
                .help(eos.version.isEmpty ? "" : "Eos v\(eos.version)")
            DetailLine(label: "Showfile:", value: eos.showName.isEmpty ? "—" : eos.showName)
            DetailLine(label: "Video Cuelist:", value: videoCueList.text, isError: videoCueList.isError)
        }
    }

    private var videoCueList: (text: String, isError: Bool) {
        guard let number = settings.eosCueList else { return ("None Chosen in Settings", false) }
        guard eos.status == .connected else { return ("\(number)", false) }
        guard let lists = eos.consoleCueLists else { return ("\(number) (Checking…)", false) }
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
        case .disconnected: return "Not Connected"
        case .error(let reason): return reason
        }
    }
}

/// "● QLab", in bold, with the reason after it when not connected.
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
        case .connected: return "QLab: \(qlab.connectedWorkspace?.displayName ?? "Connected")"
        case .connecting: return "QLab: Connecting…"
        case .waitingForWorkspace(let reason): return "QLab: \(reason)"
        case .disconnected: return "QLab: Not Connected"
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
            var parts = ["Eos: Connected"]
            if !eos.version.isEmpty { parts.append("v\(eos.version)") }
            if !eos.showName.isEmpty { parts.append(eos.showName) }
            return parts.joined(separator: " · ")
        case .connecting: return "Eos: Connecting…"
        case .notConfigured(let reason): return "Eos: \(reason)"
        case .disconnected: return "Eos: Not Connected"
        case .error(let reason): return "Eos: \(reason)"
        }
    }
}

/// Saves the window's size and position as it changes, and restores them when the window opens,
/// including when the main window is reopened after being closed. (SwiftUI's windows don't
/// save their frame under an autosave name, so this stores it in UserDefaults directly.)
private struct RemembersWindowFrame: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView { FrameView(key: "WindowFrame.\(name)") }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FrameView: NSView {
        let key: String
        private var observers: [NSObjectProtocol] = []

        init(key: String) {
            self.key = key
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard observers.isEmpty, let window else { return }
            // Wait a turn so this runs after SwiftUI has given the window its default frame.
            DispatchQueue.main.async { [key] in
                if let saved = UserDefaults.standard.string(forKey: key) {
                    window.setFrame(from: saved)
                }
                let save: (Notification) -> Void = { notification in
                    guard let window = notification.object as? NSWindow else { return }
                    UserDefaults.standard.set(window.frameDescriptor, forKey: key)
                }
                self.observers = [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification]
                    .map { NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main, using: save) }
            }
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
        .padding(.horizontal, Layout.edge)
        .padding(.vertical, 10)
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
        .padding(.horizontal, Layout.edge)
        .padding(.vertical, Layout.rowGap)
    }
}
