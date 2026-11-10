import Foundation

/// One cue (or cue part) in an Eos cue list.
public struct EosCue: Identifiable, Hashable {
    public let list: Int
    /// Cue number as Eos reports it, e.g. "1" or "1.5".
    public let number: String
    /// 0 for the cue itself, 1 or more for a part of a multipart cue.
    public let part: Int
    /// Position of this entry in the cue list (0-based).
    public let index: Int
    public let uid: String
    public let label: String
    /// Up time in milliseconds, if Eos sent one.
    public let upTimeMs: Int?

    public var id: String { uid.isEmpty ? "\(list)/\(number)/\(part)" : uid }
    public var isPart: Bool { part > 0 }

    public init(list: Int, number: String, part: Int, index: Int, uid: String, label: String, upTimeMs: Int?) {
        self.list = list
        self.number = number
        self.part = part
        self.index = index
        self.uid = uid
        self.label = label
        self.upTimeMs = upTimeMs
    }
}

/// OSC requests sent to Eos.
public enum EosRequest {
    public static let ping = OSCMessage("/eos/ping")
    public static let version = OSCMessage("/eos/get/version")
    /// Ask Eos to send `/eos/out/notify/...` when show data changes.
    public static let subscribe = OSCMessage("/eos/subscribe", [.int(1)])

    /// How many cue lists the show has.
    public static let cueListCount = OSCMessage("/eos/get/cuelist/count")

    /// Request the cue list at a 0-based position in the show's cue lists.
    public static func cueList(index: Int) -> OSCMessage {
        OSCMessage("/eos/get/cuelist/index/\(index)")
    }

    public static func cueCount(list: Int) -> OSCMessage {
        OSCMessage("/eos/get/cue/\(list)/count")
    }

    /// Request the cue at a 0-based position in a cue list.
    public static func cue(list: Int, index: Int) -> OSCMessage {
        OSCMessage("/eos/get/cue/\(list)/index/\(index)")
    }
}

/// An OSC message from Eos that this app cares about.
public enum EosOutput: Equatable {
    case cueCount(list: Int, count: Int)
    /// How many cue lists the show has.
    case cueListCount(Int)
    /// One of the show's cue lists, at a 0-based position.
    case cueList(number: Int, index: Int, label: String)
    /// The show's cue lists changed; re-read them.
    case cueListsChanged
    case cue(EosCue)
    /// Show data for this cue list changed; re-read it.
    case cueListChanged(list: Int)
    case activeCue(list: Int, number: String, progress: Double)
    case activeCueText(String)
    case pendingCue(list: Int, number: String)
    case pendingCueText(String)
    case version(String)
    case showName(String)
    /// A show was loaded or cleared; re-read everything.
    case showReset
    /// The text on an Eos command line, e.g. "LIVE: Cue 1/5 Time 0 #".
    /// `user` is nil for `/eos/out/cmd` and the user number for `/eos/out/user/<n>/cmd`.
    case commandLine(user: Int?, text: String)
    case ping
    case other

    public static func parse(_ message: OSCMessage) -> EosOutput {
        let parts = message.addressComponents
        guard parts.count >= 3, parts[0] == "eos", parts[1] == "out" else { return .other }
        let rest = Array(parts.dropFirst(2))
        let args = message.arguments

        switch rest.first ?? "" {
        case "ping":
            return .ping

        case "cmd":
            if rest.count == 1 { return .commandLine(user: nil, text: args.first?.stringValue ?? "") }
            return .other

        case "user":
            // /eos/out/user/<n>/cmd
            if rest.count == 3, rest[2] == "cmd", let user = Int(rest[1]) {
                return .commandLine(user: user, text: args.first?.stringValue ?? "")
            }
            return .other

        case "get":
            if rest == ["get", "version"], let version = args.first?.stringValue {
                return .version(version)
            }
            // /eos/out/get/cuelist/count = <count>
            if rest == ["get", "cuelist", "count"], let count = args.first?.intValue {
                return .cueListCount(count)
            }
            // /eos/out/get/cuelist/<list>/list/<offset>/<argument count>
            // args: 0 index, 1 uid, 2 label, ... (offset 0 only, as for cues; "links" replies ignored)
            if rest.count == 6, rest[1] == "cuelist", rest[3] == "list", rest[4] == "0",
               let number = Int(rest[2]), let index = args.first?.intValue {
                return .cueList(number: number, index: index,
                                label: args.count > 2 ? (args[2].stringValue ?? "") : "")
            }
            // /eos/out/get/cue/<list>/count = <count>
            if rest.count == 4, rest[1] == "cue", rest[3] == "count",
               let list = Int(rest[2]), let count = args.first?.intValue {
                return .cueCount(list: list, count: count)
            }
            // /eos/out/get/cue/<list>/<cue>/<part>/list/<offset>/<argument count>
            // args: 0 index (position in the cue list), 1 uid, 2 label, 3 up time (ms), ...
            // The trailing pair describes the argument list, not the cue list: <offset> is the
            // first argument carried by this message. Only offset 0 has the fields read here.
            // Eos sends extra replies with fx/links/actions before "list"; those are ignored.
            if rest.count == 8, rest[1] == "cue", rest[5] == "list", rest[6] == "0",
               let list = Int(rest[2]), let part = Int(rest[4]),
               let index = args.first?.intValue {
                let cue = EosCue(
                    list: list,
                    number: rest[3],
                    part: part,
                    index: index,
                    uid: args.count > 1 ? (args[1].stringValue ?? "") : "",
                    label: args.count > 2 ? (args[2].stringValue ?? "") : "",
                    upTimeMs: args.count > 3 ? args[3].intValue : nil
                )
                return .cue(cue)
            }
            return .other

        case "notify":
            // /eos/out/notify/cuelist/...
            if rest.count >= 2, rest[1] == "cuelist" {
                return .cueListsChanged
            }
            // /eos/out/notify/cue/<list>/...
            if rest.count >= 3, rest[1] == "cue", let list = Int(rest[2]) {
                return .cueListChanged(list: list)
            }
            return .other

        case "active", "pending":
            let isActive = rest[0] == "active"
            guard rest.count >= 2, rest[1] == "cue" else { return .other }
            if rest.count == 3, rest[2] == "text" {
                let text = args.first?.stringValue ?? ""
                return isActive ? .activeCueText(text) : .pendingCueText(text)
            }
            // /eos/out/active/cue/<list>/<cue> = <progress 0..1>
            if rest.count == 4, let list = Int(rest[2]) {
                if isActive {
                    return .activeCue(list: list, number: rest[3], progress: args.first?.doubleValue ?? 0)
                }
                return .pendingCue(list: list, number: rest[3])
            }
            return .other

        case "show":
            if rest == ["show", "name"] { return .showName(args.first?.stringValue ?? "") }
            if rest == ["show", "loaded"] || rest == ["show", "cleared"] { return .showReset }
            return .other

        default:
            return .other
        }
    }
}

/// Validates the Eos cue list number typed by the user. There is deliberately no default.
public enum EosCueListNumber {
    public static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value >= 1, value <= 999 else { return nil }
        return value
    }
}
