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
        case actions = "Action log"
        case connection = "Connection log"
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
            .frame(maxWidth: 520)
            .padding(.vertical, 8)

            Group {
                switch tab {
                case .compare: ComparisonPane()
                case .actions: ActionLogPane()
                case .connection: ConnectionLogPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(width: 580, height: 720)
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

// MARK: - Log

struct ConnectionLogPane: View {
    @EnvironmentObject private var log: ConnectionLog

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connection log").font(.headline)
                Spacer()
                Button("Clear") { log.clear() }
                    .disabled(log.log.lines.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if log.log.lines.isEmpty {
                Placeholder(text: "No connection events yet.")
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
                    .padding(.horizontal, 10)
                }
            }
        }
    }
}
