import Foundation

/// Text for the printable cue list (PDF export): one line per QLab cue.
public enum CueSheet {
    /// The start of a cue's line, up to its name, e.g. "• 3.5 - ". Long names wrap to line up
    /// after this, so it is measured separately from the name.
    public static func prefix(number: String) -> String {
        "• \(number) - "
    }

    /// A cue's whole line, e.g. "• 3.5 - Ghost enters".
    public static func line(number: String, name: String) -> String {
        prefix(number: number) + name
    }

    /// The suggested file name, e.g. "Hamlet - Main Cue List.pdf". Characters macOS doesn't
    /// allow in file names ("/" and ":") become "-".
    public static func fileName(workspace: String, cueList: String) -> String {
        let name = [workspace, cueList]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let safe = String(name.map { $0 == "/" || $0 == ":" ? "-" : $0 })
        return (safe.isEmpty ? "Cue List" : safe) + ".pdf"
    }
}
