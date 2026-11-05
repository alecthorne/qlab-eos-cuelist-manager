import Foundation

/// Rules for Eos cue numbers.
public enum EosCueNumber {
    /// Most digits allowed after the decimal point.
    public static let maxDecimalPlaces = 4
    /// Largest whole-number part allowed.
    public static let maxWholeNumber = 9999

    /// The canonical form of a cue number ("01.50" becomes "1.5"), or nil if Eos
    /// can't use it as a cue number (e.g. "1A", "Pre", "0", "").
    public static func canonical(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2 else { return nil }

        let wholeText = pieces[0]
        guard !wholeText.isEmpty, wholeText.allSatisfy(isDigit) else { return nil }

        var fraction = ""
        if pieces.count == 2 {
            fraction = String(pieces[1])
            guard !fraction.isEmpty, fraction.allSatisfy(isDigit) else { return nil }
            while fraction.hasSuffix("0") { fraction.removeLast() }
        }
        guard fraction.count <= maxDecimalPlaces else { return nil }

        var whole = String(wholeText.drop { $0 == "0" })
        if whole.isEmpty { whole = "0" }
        guard whole.count <= String(maxWholeNumber).count,
              let wholeValue = Int(whole), wholeValue <= maxWholeNumber else { return nil }
        guard !(wholeValue == 0 && fraction.isEmpty) else { return nil }

        return fraction.isEmpty ? whole : "\(whole).\(fraction)"
    }

    /// Sorts canonical cue numbers numerically ("2" before "10", "1.25" before "1.5").
    public static func isOrderedBefore(_ a: String, _ b: String) -> Bool {
        sortKey(a) < sortKey(b)
    }

    static func sortKey(_ canonical: String) -> SortKey {
        let pieces = canonical.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(pieces[0]) ?? Int.max
        var fraction = pieces.count > 1 ? String(pieces[1]) : ""
        while fraction.count < maxDecimalPlaces { fraction.append("0") }
        return SortKey(whole: whole, fraction: Int(fraction) ?? 0)
    }

    struct SortKey: Comparable {
        let whole: Int
        let fraction: Int

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            (lhs.whole, lhs.fraction) < (rhs.whole, rhs.fraction)
        }
    }

    private static func isDigit(_ c: Character) -> Bool {
        c.isASCII && c.isNumber
    }
}

/// One line of the QLab-versus-Eos comparison.
public struct CueComparisonRow: Identifiable, Equatable {
    public enum Status: Equatable, CaseIterable {
        /// Same number and label on both sides.
        case match
        /// Cue exists on both sides but the Eos label differs from the QLab name.
        case labelDiffers
        /// QLab has this cue number; Eos does not.
        case missingInEos
        /// Eos has this cue number; QLab does not.
        case extraInEos
        /// The QLab cue number can't be an Eos cue number (e.g. "1A").
        case invalidQLabNumber
        /// More than one QLab cue maps to this Eos cue number.
        case duplicateQLabNumber
    }

    public let id: String
    /// Canonical cue number, or nil when the QLab number isn't valid for Eos.
    public let number: String?
    public let qlab: QLabCue?
    public let eos: EosCue?
    public let status: Status

    /// True when Eos doesn't match QLab for this row.
    public var isMismatch: Bool { status != .match }
}

public enum CueComparison {
    /// Compares the numbered QLab cues (the source of truth) with the cues in the Eos list.
    /// Eos cue parts are left out: only whole cues are compared.
    /// Rows are in cue number order; QLab cues with invalid numbers come last, in QLab order.
    public static func compare(qlab: [QLabCue], eos: [EosCue]) -> [CueComparisonRow] {
        var qlabByNumber: [String: [QLabCue]] = [:]
        var invalid: [QLabCue] = []
        for cue in qlab {
            if let number = EosCueNumber.canonical(cue.number) {
                qlabByNumber[number, default: []].append(cue)
            } else {
                invalid.append(cue)
            }
        }

        var eosByNumber: [String: EosCue] = [:]
        for cue in eos where !cue.isPart {
            let number = EosCueNumber.canonical(cue.number) ?? cue.number
            if eosByNumber[number] == nil { eosByNumber[number] = cue }
        }

        let numbers = Set(qlabByNumber.keys).union(eosByNumber.keys)
            .sorted(by: EosCueNumber.isOrderedBefore)

        var rows: [CueComparisonRow] = []
        for number in numbers {
            let qlabCues = qlabByNumber[number] ?? []
            let eosCue = eosByNumber[number]

            switch qlabCues.count {
            case 0:
                rows.append(CueComparisonRow(id: "n-\(number)", number: number, qlab: nil, eos: eosCue, status: .extraInEos))
            case 1:
                let qlabCue = qlabCues[0]
                let status: CueComparisonRow.Status
                if let eosCue {
                    status = labelsMatch(qlabCue.displayName, eosCue.label) ? .match : .labelDiffers
                } else {
                    status = .missingInEos
                }
                rows.append(CueComparisonRow(id: "n-\(number)", number: number, qlab: qlabCue, eos: eosCue, status: status))
            default:
                for qlabCue in qlabCues {
                    rows.append(CueComparisonRow(id: "dup-\(qlabCue.id)", number: number, qlab: qlabCue, eos: eosCue, status: .duplicateQLabNumber))
                }
            }
        }

        for cue in invalid {
            rows.append(CueComparisonRow(id: "bad-\(cue.id)", number: nil, qlab: cue, eos: nil, status: .invalidQLabNumber))
        }
        return rows
    }

    public static func labelsMatch(_ qlabName: String, _ eosLabel: String) -> Bool {
        qlabName.trimmingCharacters(in: .whitespaces) == eosLabel.trimmingCharacters(in: .whitespaces)
    }

    /// How many rows have each status.
    public static func counts(_ rows: [CueComparisonRow]) -> [CueComparisonRow.Status: Int] {
        var counts: [CueComparisonRow.Status: Int] = [:]
        for row in rows { counts[row.status, default: 0] += 1 }
        return counts
    }
}
