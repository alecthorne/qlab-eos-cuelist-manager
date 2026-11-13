import CueSyncCore
import SwiftUI

/// QLab cues and Eos cues lined up by cue number, with every difference flagged.
struct ComparisonPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var eos: EosClient
    @State private var onlyDifferences = false

    var body: some View {
        if let notReady = model.comparisonNotReadyReason {
            Placeholder(text: notReady)
        } else {
            let rows = model.comparisonRows ?? []
            let shown = onlyDifferences ? rows.filter(\.isMismatch) : rows
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cues").font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    HStack(spacing: 16) {
                        Summary(rows: rows)
                        Spacer()
                        if eos.isLoadingCues {
                            ProgressView().controlSize(.small)
                        }
                        Toggle("Only Show Differences", isOn: $onlyDifferences)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                    Table(shown) {
                        TableColumn("QLab Cue Name") { row in
                            Text(row.qlab?.displayName ?? "")
                        }
                        TableColumn("QLab Cue #") { row in
                            Text(row.qlab?.number ?? "")
                        }
                        .width(min: 60, ideal: 80, max: 120)
                        TableColumn("Status") { row in
                            StatusBadge(status: row.status)
                        }
                        .width(min: 130, ideal: 160, max: 220)
                        TableColumn("Eos Cue #") { row in
                            HStack(spacing: 4) {
                                if isActive(row) {
                                    Text("▶").foregroundStyle(.green)
                                }
                                Text(row.eos?.number ?? "")
                            }
                        }
                        .width(min: 60, ideal: 80, max: 120)
                        TableColumn("Eos Cue Label") { row in
                            Text(row.eos?.label ?? "")
                                .foregroundStyle(row.status == .labelDiffers ? Color.orange : Color.primary)
                        }
                    }
                }
                .frame(minWidth: 520)

                ApprovalPanel(changes: model.plannedChanges ?? [])
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
            }
        }
    }

    private func isActive(_ row: CueComparisonRow) -> Bool {
        guard let active = eos.activeCue, let cue = row.eos else { return false }
        return active.list == cue.list && active.number == cue.number
    }
}

struct StatusBadge: View {
    let status: CueComparisonRow.Status

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(title)
        }
        .help(explanation)
    }

    var title: String { Self.title(status) }

    static func title(_ status: CueComparisonRow.Status) -> String {
        switch status {
        case .match: return "Matches"
        case .labelDiffers: return "Label Differs"
        case .missingInEos: return "Missing in Eos"
        case .extraInEos: return "Not in QLab"
        case .invalidQLabNumber: return "Not a Valid Eos Cue #"
        case .duplicateQLabNumber: return "Duplicate Number"
        }
    }

    private var symbol: String {
        switch status {
        case .match: return "checkmark.circle.fill"
        case .labelDiffers: return "pencil.circle.fill"
        case .missingInEos: return "plus.circle.fill"
        case .extraInEos: return "minus.circle.fill"
        case .invalidQLabNumber: return "exclamationmark.triangle.fill"
        case .duplicateQLabNumber: return "exclamationmark.octagon.fill"
        }
    }

    var color: Color { Self.color(status) }

    static func color(_ status: CueComparisonRow.Status) -> Color {
        switch status {
        case .match: return .green
        case .labelDiffers: return .orange
        case .missingInEos: return .blue
        case .extraInEos: return .red
        case .invalidQLabNumber: return .yellow
        case .duplicateQLabNumber: return .purple
        }
    }

    private var explanation: String {
        switch status {
        case .match: return "Same number and label in QLab and Eos."
        case .labelDiffers: return "The Eos label doesn't match the QLab name. You can approve updating it in the panel on the right."
        case .missingInEos: return "QLab has this cue number but Eos doesn't. You can approve adding it in the panel on the right."
        case .extraInEos: return "Eos has this cue but QLab doesn't. You can approve deleting it in the panel on the right."
        case .invalidQLabNumber: return "This QLab cue number can't be used as an Eos cue number (Eos needs a number like 12 or 12.5). Renumber it in QLab to sync it."
        case .duplicateQLabNumber: return "More than one QLab cue has this number. Fix it in QLab; nothing will be synced for this number until then."
        }
    }
}

private struct Summary: View {
    let rows: [CueComparisonRow]

    var body: some View {
        let counts = CueComparison.counts(rows)
        let mismatches = rows.filter(\.isMismatch).count
        HStack(spacing: 12) {
            Text(mismatches == 0 ? "Eos matches QLab" : "\(mismatches) Difference\(mismatches == 1 ? "" : "s")")
                .font(.headline)
                .foregroundStyle(mismatches == 0 ? Color.green : Color.primary)
            ForEach(CueComparisonRow.Status.allCases.filter { $0 != .match && (counts[$0] ?? 0) > 0 }, id: \.self) { status in
                HStack(spacing: 4) {
                    Circle().fill(StatusBadge.color(status)).frame(width: 8, height: 8)
                    Text("\(counts[status] ?? 0) \(StatusBadge.title(status))")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Placeholder: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
