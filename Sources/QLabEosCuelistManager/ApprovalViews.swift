import CueSyncCore
import SwiftUI

/// Lists every change Eos needs, one card each. Nothing is sent until you press Approve.
struct ApprovalPanel: View {
    let changes: [EosChange]
    @EnvironmentObject private var controller: ChangeController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        let visible = changes.filter { !controller.skipped.contains($0.id) }
        let skippedCount = changes.count - visible.count
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Changes to approve").font(.headline)
                Spacer()
                Text("\(visible.count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if let reason = controller.blockedReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            } else if let error = controller.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            if visible.isEmpty {
                Placeholder(text: changes.isEmpty ? "Nothing to change. Eos matches QLab." : "All remaining changes are skipped.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(visible) { change in
                            ChangeCard(change: change)
                        }
                    }
                    .padding(10)
                }
            }

            if skippedCount > 0 {
                Divider()
                HStack {
                    Text("\(skippedCount) skipped").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show skipped") { controller.restoreSkipped() }
                }
                .padding(10)
            }
        }
        .onChange(of: changes) { newValue in
            controller.prune(current: newValue)
        }
    }
}

struct ChangeCard: View {
    let change: EosChange
    @EnvironmentObject private var controller: ChangeController
    // Observed so the Approve button updates when the connection or settings change.
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        let state = controller.states[change.id]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(change.kind.rawValue.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(kindColor.opacity(0.2))
                    .foregroundStyle(kindColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(change.summary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(controller.commands(for: change).enumerated()), id: \.offset) { _, command in
                    Text(command.displayText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack {
                switch state {
                case .some(.sent):
                    ProgressView().controlSize(.small)
                    Text("Sent, waiting for Eos…").foregroundStyle(.secondary)
                case .some(.notConfirmed):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Eos still differs. Check the console, then try again.")
                        .font(.callout)
                case .none:
                    EmptyView()
                }
                Spacer()
                Button("Skip") { controller.skip(change) }
                    .disabled(state == .sent)
                Button(state == .notConfirmed ? "Try again" : "Approve") { controller.approve(change) }
                    .buttonStyle(.borderedProminent)
                    .tint(change.kind == .delete ? Color.red : Color.accentColor)
                    .disabled(state == .sent || controller.blockedReason != nil)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
    }

    private var kindColor: Color {
        switch change.kind {
        case .add: return .blue
        case .updateLabel: return .orange
        case .delete: return .red
        }
    }
}

/// The add/edit/delete history, newest first (500 lines kept).
struct ActionLogPane: View {
    @EnvironmentObject private var actionLog: ActionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Action log").font(.headline)
                Text("\(actionLog.log.lines.count) of \(actionLog.log.capacity) lines")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy all") { actionLog.copyToPasteboard() }
                    .disabled(actionLog.log.lines.isEmpty)
                Button("Clear") { actionLog.clear() }
                    .disabled(actionLog.log.lines.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if actionLog.log.lines.isEmpty {
                Placeholder(text: "No changes sent to Eos yet.")
            } else {
                Table(Array(actionLog.log.lines.reversed())) {
                    TableColumn("Time") { entry in
                        Text(ActionLog.timeFormatter.string(from: entry.date))
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 140, ideal: 160, max: 180)
                    TableColumn("Action") { entry in Text(entry.kind.rawValue) }
                        .width(min: 50, ideal: 60, max: 80)
                    TableColumn("Change") { entry in Text(entry.summary) }
                    TableColumn("Result") { entry in Text(entry.result) }
                        .width(min: 100, ideal: 180, max: 260)
                    TableColumn("Commands sent") { entry in
                        Text(entry.commands.joined(separator: "  |  "))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
