import AppKit
import CueSyncCore
import Foundation

struct ActionLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let kind: EosChange.Kind
    let summary: String
    let commands: [String]
    var result: String

    var line: String {
        "\(ActionLog.timeFormatter.string(from: date))  \(kind.rawValue.uppercased())  \(summary)  [\(result)]  " +
            commands.joined(separator: " | ")
    }
}

/// Every add, edit and delete sent to Eos. Keeps the newest 500 lines.
final class ActionLog: ObservableObject {
    @Published private(set) var log = BoundedLog<ActionLogEntry>(capacity: 500)

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    @discardableResult
    func add(_ change: EosChange, commands: [EosCommand], result: String) -> UUID {
        let entry = ActionLogEntry(
            date: Date(),
            kind: change.kind,
            summary: change.summary,
            commands: commands.map(\.displayText),
            result: result
        )
        log.append(entry)
        return entry.id
    }

    func setResult(_ id: UUID, _ result: String) {
        log.updateLast(where: { $0.id == id }) { $0.result = result }
    }

    func copyToPasteboard() {
        let text = log.lines.map(\.line).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clear() {
        log.removeAll()
    }
}

/// Tracks the changes waiting for approval, sends the ones the user approves,
/// and checks that Eos really changed afterwards.
final class ChangeController: ObservableObject {
    enum State: Equatable {
        /// Sent; waiting for the Eos cue list to show the change.
        case sent
        /// Sent, but Eos still didn't match a few seconds later.
        case notConfirmed
    }

    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var skipped: Set<String> = []
    @Published private(set) var lastError: String?

    private let actionLog: ActionLog
    private let settings: AppSettings
    private let eos: EosClient
    /// The changes still needed right now (recomputed from the latest QLab and Eos data).
    /// nil when the two sides aren't both loaded.
    private let currentChanges: () -> [EosChange]?

    /// How long to wait for Eos to report the change before calling it unconfirmed.
    private let confirmDelay: TimeInterval = 6

    init(actionLog: ActionLog, settings: AppSettings, eos: EosClient, currentChanges: @escaping () -> [EosChange]?) {
        self.actionLog = actionLog
        self.settings = settings
        self.eos = eos
        self.currentChanges = currentChanges
    }

    func commands(for change: EosChange) -> [EosCommand] {
        EosCommandBuilder.commands(for: change, addTemplate: settings.eosAddTemplate)
    }

    /// Why changes can't be sent right now, or nil if they can.
    var blockedReason: String? {
        if eos.status != .connected { return "Eos is not connected." }
        if settings.eosUser == nil { return "The Eos user number in Settings isn't valid." }
        if settings.eosAddTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
            return "The command for adding a cue is empty in Settings."
        }
        return nil
    }

    func approve(_ change: EosChange) {
        lastError = nil
        guard blockedReason == nil, let user = settings.eosUser else {
            lastError = blockedReason
            return
        }
        guard states[change.id] != .sent else { return }

        let commands = commands(for: change)
        guard eos.send(commands, user: user) else {
            lastError = "Could not send to Eos."
            actionLog.add(change, commands: commands, result: "Not sent: Eos not connected")
            return
        }
        let logID = actionLog.add(change, commands: commands, result: "Sent")
        states[change.id] = .sent

        // Eos normally reports the change itself; re-read anyway in case it doesn't.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.eos.refreshCues()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmDelay) { [weak self] in
            self?.checkResult(of: change, logID: logID)
        }
    }

    func skip(_ change: EosChange) {
        skipped.insert(change.id)
    }

    func restoreSkipped() {
        skipped.removeAll()
    }

    /// Forgets state for changes that are no longer needed (Eos now matches).
    func prune(current: [EosChange]) {
        let ids = Set(current.map(\.id))
        let staleStates = states.keys.filter { !ids.contains($0) && states[$0] != .sent }
        staleStates.forEach { states.removeValue(forKey: $0) }
        let staleSkips = skipped.filter { !ids.contains($0) }
        if !staleSkips.isEmpty { skipped.subtract(staleSkips) }
    }

    private func checkResult(of change: EosChange, logID: UUID) {
        guard let current = currentChanges() else {
            states.removeValue(forKey: change.id)
            actionLog.setResult(logID, "Sent; couldn't check (cue lists not loaded)")
            return
        }
        if current.contains(where: { $0.id == change.id }) {
            states[change.id] = .notConfirmed
            actionLog.setResult(logID, "Sent, but Eos still differs")
        } else {
            states.removeValue(forKey: change.id)
            actionLog.setResult(logID, "Confirmed")
        }
    }
}
