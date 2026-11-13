import Foundation

/// QLab's OSC Access passcodes are four-digit numbers. Empty means connect without one.
public enum QLabPasscode {
    public static func isValid(_ text: String) -> Bool {
        text.isEmpty || (text.count == 4 && text.allSatisfy { $0.isASCII && $0.isNumber })
    }
}

/// A reply from QLab: `/reply/{invoked address}` with one JSON string argument.
public struct QLabReply {
    /// The address that was invoked, e.g. `/workspace/ABC/cueLists`.
    public let address: String
    public let workspaceID: String?
    /// `ok`, `error` or `denied`.
    public let status: String
    public let data: Any?

    public var isOK: Bool { status == "ok" }

    /// The permissions QLab granted in a `/connect` reply, e.g. "ok:view|edit|control" →
    /// ["view", "edit", "control"]. "ok:" (nothing granted) gives an empty set. nil means the
    /// reply didn't list permissions (older QLab versions reply just "ok").
    public static func connectPermissions(_ result: String) -> Set<String>? {
        guard let colon = result.firstIndex(of: ":") else { return nil }
        return Set(result[result.index(after: colon)...].split(separator: "|").map { String($0) })
    }

    public static func parse(_ message: OSCMessage) -> QLabReply? {
        guard message.address.hasPrefix("/reply"),
              let json = message.arguments.first?.stringValue,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let dict = object as? [String: Any] else { return nil }
        let replyAddress = (dict["address"] as? String)
            ?? String(message.address.dropFirst("/reply".count))
        return QLabReply(
            address: replyAddress,
            workspaceID: dict["workspace_id"] as? String,
            status: dict["status"] as? String ?? "",
            data: dict["data"]
        )
    }
}

public struct QLabWorkspace: Identifiable, Hashable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// Parses the `data` of a `/workspaces` reply.
    public static func parseList(_ data: Any?) -> [QLabWorkspace] {
        guard let array = data as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let id = dict["uniqueID"] as? String else { return nil }
            return QLabWorkspace(id: id, displayName: dict["displayName"] as? String ?? id)
        }
    }
}

/// A QLab cue (or cue list, or group) as returned by `/workspace/{id}/cueLists`.
public struct QLabCue: Identifiable, Hashable {
    public let id: String
    public let number: String
    public let name: String
    /// The name as displayed in QLab's cue list (falls back to QLab's default name).
    public let listName: String
    public let type: String
    public let children: [QLabCue]

    public init(id: String, number: String, name: String, listName: String, type: String, children: [QLabCue] = []) {
        self.id = id
        self.number = number
        self.name = name
        self.listName = listName
        self.type = type
        self.children = children
    }

    /// The label to show for this cue: QLab's displayed name, or the raw name.
    public var displayName: String { listName.isEmpty ? name : listName }

    public static func parse(_ dict: [String: Any]) -> QLabCue? {
        guard let id = dict["uniqueID"] as? String else { return nil }
        return QLabCue(
            id: id,
            number: dict["number"] as? String ?? "",
            name: dict["name"] as? String ?? "",
            listName: dict["listName"] as? String ?? "",
            type: dict["type"] as? String ?? "",
            children: parseList(dict["cues"])
        )
    }

    /// Parses an array of cue dictionaries, such as the `data` of a `cueLists` reply.
    public static func parseList(_ data: Any?) -> [QLabCue] {
        guard let array = data as? [[String: Any]] else { return [] }
        return array.compactMap(parse)
    }

    /// Every cue inside this one, at any depth, that has a cue number, in cue list order.
    /// Group cues that have a number are included as well as their children.
    public func numberedDescendants() -> [QLabCue] {
        var result: [QLabCue] = []
        for child in children {
            if !child.number.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(child)
            }
            result.append(contentsOf: child.numberedDescendants())
        }
        return result
    }
}
