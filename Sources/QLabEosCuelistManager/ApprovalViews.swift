import CueSyncCore
import SwiftUI

/// Lists every change Eos needs, one card each. Nothing is sent until you press Approve.
struct ApprovalPanel: View {
    let changes: [EosChange]
    @EnvironmentObject private var controller: ChangeController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eos: EosClient
    @State private var confirmingApproveAll = false

    var body: some View {
        let visible = changes.filter { !controller.skipped.contains($0.id) }
        let skippedCount = changes.count - visible.count
        let sendable = visible.filter(controller.canSend)
        let labelEdits = sendable.filter { $0.kind == .updateLabel }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Changes to approve").font(.headline)
                Spacer()
                Text("\(visible.count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            HStack {
                Button("Approve All") { confirmingApproveAll = true }
                    .disabled(sendable.isEmpty || controller.blockedReason != nil)
                Button("Update Eos Cue Labels") { controller.approve(labelEdits) }
                    .disabled(labelEdits.isEmpty || controller.blockedReason != nil)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

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
        .confirmationDialog(
            "Send \(sendable.count) change\(sendable.count == 1 ? "" : "s") to Eos?",
            isPresented: $confirmingApproveAll
        ) {
            Button("Approve All", role: sendable.contains { $0.kind == .delete } ? .destructive : nil) {
                controller.approve(sendable)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.breakdown(of: sendable) + " Skipped changes are not sent.")
        }
    }

    /// E.g. "2 adds, 1 label edit, 3 deletes."
    private static func breakdown(of changes: [EosChange]) -> String {
        let kinds: [(EosChange.Kind, String, String)] = [
            (.add, "add", "adds"),
            (.updateLabel, "label edit", "label edits"),
            (.delete, "delete", "deletes"),
        ]
        let parts = kinds.compactMap { kind, singular, plural -> String? in
            let count = changes.filter { $0.kind == kind }.count
            return count == 0 ? nil : "\(count) \(count == 1 ? singular : plural)"
        }
        return parts.joined(separator: ", ") + "."
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
                case .some(.queued):
                    ProgressView().controlSize(.small)
                    Text("Queued…").foregroundStyle(.secondary)
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
                    .disabled(!controller.canSend(change))
                Button(state == .notConfirmed ? "Try again" : "Approve") { controller.approve(change) }
                    .buttonStyle(.borderedProminent)
                    .tint(change.kind == .delete ? Color.red : Color.accentColor)
                    .disabled(!controller.canSend(change) || controller.blockedReason != nil)
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
