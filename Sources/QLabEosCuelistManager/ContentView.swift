import CueSyncCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var eos: EosClient
    @State private var showingSettings = false
    @State private var tab: Tab = .compare

    enum Tab: String, CaseIterable, Identifiable {
        case compare = "Compare"
        case eos = "Eos cue list"
        case qlab = "QLab cues"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusBar()
            Divider()

            if settings.eosCueList == nil {
                Banner(text: "Choose the Eos cue list to sync before anything else.",
                       buttonTitle: "Open Settings") { showingSettings = true }
            } else if settings.qlabCueListID.isEmpty {
                Banner(text: "Choose the QLab cue list to use as the source of truth.",
                       buttonTitle: "Open Settings") { showingSettings = true }
            }

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.vertical, 8)

            Group {
                switch tab {
                case .compare: ComparisonPane()
                case .eos: EosCuesPane()
                case .qlab: QLabCuesPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            ConnectionLogView()
        }
        .toolbar {
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
            .frame(width: 560, height: 600)
        }
        .onAppear {
            model.startIfNeeded()
            if settings.eosCueList == nil || settings.eosHost.isEmpty {
                showingSettings = true
            }
        }
    }
}

// MARK: - Status

struct StatusBar: View {
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        HStack(spacing: 24) {
            StatusLabel(qlab: qlab)
            EosStatusLabel()
            Spacer()
            HStack(spacing: 6) {
                Text("Eos active cue:")
                    .foregroundStyle(.secondary)
                Text(eos.activeCueText.isEmpty ? "None" : eos.activeCueText)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

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

// MARK: - Cue lists

struct QLabCuesPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient

    var body: some View {
        let cues = model.qlabNumberedCues
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "QLab: \(model.selectedQLabCueList?.displayName ?? "no cue list chosen")",
                detail: "\(cues.count) numbered cues"
            )
            Table(cues) {
                TableColumn("Number", value: \.number)
                    .width(min: 50, ideal: 70, max: 120)
                TableColumn("Name") { cue in Text(cue.displayName) }
                TableColumn("Type", value: \.type)
                    .width(min: 50, ideal: 80, max: 120)
            }
        }
    }
}

struct EosCuesPane: View {
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: eos.cueList.map { "Eos: cue list \($0)" } ?? "Eos: no cue list chosen",
                detail: eos.isLoadingCues ? "Loading…" : "\(eos.cues.count) cues"
            )
            Table(eos.cues) {
                TableColumn("") { cue in
                    Text(isActive(cue) ? "▶" : "")
                        .foregroundStyle(.green)
                }
                .width(16)
                TableColumn("Cue") { cue in
                    Text(cue.isPart ? "\(cue.number) pt \(cue.part)" : cue.number)
                }
                .width(min: 50, ideal: 70, max: 120)
                TableColumn("Label", value: \.label)
                TableColumn("Time") { cue in
                    Text(cue.upTimeMs.map(formatSeconds) ?? "")
                }
                .width(min: 40, ideal: 60, max: 90)
            }
        }
    }

    private func isActive(_ cue: EosCue) -> Bool {
        guard let active = eos.activeCue, !cue.isPart else { return false }
        return active.list == cue.list && active.number == cue.number
    }
}

struct PaneHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Log

struct ConnectionLogView: View {
    @EnvironmentObject private var log: ConnectionLog
    @State private var expanded = true

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
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
        } label: {
            HStack {
                Text("Connection log")
                Spacer()
                Button("Clear") { log.clear() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
