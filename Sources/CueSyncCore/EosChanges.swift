import Foundation

/// One change to make Eos match QLab. Nothing is sent until the user approves it.
public struct EosChange: Identifiable, Equatable {
    public enum Kind: String, Equatable {
        case add = "Add"
        case updateLabel = "Edit"
        case delete = "Delete"
    }

    public let kind: Kind
    public let list: Int
    /// Canonical Eos cue number.
    public let number: String
    /// The label Eos should end up with (from QLab). Empty for deletes.
    public let label: String
    /// The current Eos label, for edits and deletes.
    public let currentLabel: String?

    public var id: String { "\(kind.rawValue)-\(list)-\(number)-\(label)" }

    public init(kind: Kind, list: Int, number: String, label: String, currentLabel: String?) {
        self.kind = kind
        self.list = list
        self.number = number
        self.label = label
        self.currentLabel = currentLabel
    }

    /// A one-line description for the approval panel and the action log.
    public var summary: String {
        switch kind {
        case .add:
            return "Add cue \(list)/\(number) “\(label)”, time 0"
        case .updateLabel:
            return "Change label of cue \(list)/\(number) from “\(currentLabel ?? "")” to “\(label)”"
        case .delete:
            let existing = (currentLabel ?? "").isEmpty ? "" : " “\(currentLabel!)”"
            return "Delete cue \(list)/\(number)\(existing)"
        }
    }

    /// The changes needed to make the Eos list match QLab, in cue number order.
    /// Rows that need fixing in QLab (invalid or duplicate numbers) produce no change.
    public static func plan(from rows: [CueComparisonRow], list: Int) -> [EosChange] {
        rows.compactMap { row in
            guard let number = row.number else { return nil }
            switch row.status {
            case .missingInEos:
                guard let qlab = row.qlab else { return nil }
                return EosChange(kind: .add, list: list, number: number, label: cleanLabel(qlab.displayName), currentLabel: nil)
            case .labelDiffers:
                guard let qlab = row.qlab, let eos = row.eos else { return nil }
                return EosChange(kind: .updateLabel, list: list, number: number, label: cleanLabel(qlab.displayName), currentLabel: eos.label)
            case .extraInEos:
                return EosChange(kind: .delete, list: list, number: number, label: "", currentLabel: row.eos?.label)
            case .match, .invalidQLabNumber, .duplicateQLabNumber:
                return nil
            }
        }
    }

    static func cleanLabel(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}

/// One message sent to Eos for a change.
public enum EosCommand: Equatable {
    /// A command line, sent with `/eos/newcmd` (which clears the command line first).
    /// `%1`, `%2`… in the text are filled from `arguments` by Eos.
    case commandLine(String, arguments: [String] = [])
    /// Sets a cue's label with `/eos/set/cue/<list>/<cue>/label`, the label as an OSC string.
    /// Nothing is typed on a command line, so any text is safe and it works in any mode.
    case setCueLabel(list: Int, number: String, label: String)

    /// A command line with no arguments.
    public static func line(_ text: String) -> EosCommand { .commandLine(text, arguments: []) }

    /// The command line text, or nil for messages that don't use the command line.
    public var text: String? {
        if case .commandLine(let text, _) = self { return text }
        return nil
    }

    /// How the command reads, for showing to the user and in the action log.
    public var displayText: String {
        switch self {
        case .commandLine(let text, let arguments):
            var result = text
            for (index, argument) in arguments.enumerated().reversed() {
                result = result.replacingOccurrences(of: "%\(index + 1)", with: "“\(argument)”")
            }
            return result
        case .setCueLabel(let list, let number, let label):
            return "Set label of cue \(list)/\(number) to “\(label)”"
        }
    }

    /// The OSC message. For command lines, `user` sends it as that Eos user
    /// (`/eos/user/<n>/newcmd`), so the operator's own command line isn't touched;
    /// nil uses the console's current user.
    public func message(user: Int?) -> OSCMessage {
        switch self {
        case .commandLine(let text, let arguments):
            let prefix = user.map { "/eos/user/\($0)" } ?? "/eos"
            return OSCMessage(prefix + "/newcmd", [.string(text)] + arguments.map { .string($0) })
        case .setCueLabel(let list, let number, let label):
            return OSCMessage("/eos/set/cue/\(list)/\(number)/label", [.string(label)])
        }
    }
}

public enum EosCommandBuilder {
    /// The default command for creating a blank cue. `{list}` and `{cue}` are filled in.
    /// Record Only stores only manual data, so with nothing manual on stage the cue is blank.
    public static let defaultAddTemplate = "Record Only Cue {list}/{cue}#"

    public static func commands(for change: EosChange, addTemplate: String = defaultAddTemplate) -> [EosCommand] {
        let cue = "Cue \(change.list)/\(change.number)"
        let label = EosCommand.setCueLabel(list: change.list, number: change.number, label: change.label)
        switch change.kind {
        case .add:
            let create = addTemplate
                .replacingOccurrences(of: "{list}", with: String(change.list))
                .replacingOccurrences(of: "{cue}", with: change.number)
            return [.line(create), .line("\(cue) Time 0#"), label]
        case .updateLabel:
            return [label]
        case .delete:
            // The second Enter confirms the delete.
            return [.line("Delete \(cue) Enter Enter")]
        }
    }
}

/// Validates the optional Eos OSC user number. Empty means "use the current user".
public enum EosUserNumber {
    public static func parse(_ text: String) -> Int?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Int(trimmed), (0...99).contains(value) else { return nil }
        return .some(value)
    }
}
