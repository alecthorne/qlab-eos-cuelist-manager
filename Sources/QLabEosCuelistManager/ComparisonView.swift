import CueSyncCore
import SwiftUI

/// QLab cues and Eos cues lined up by cue number, with every difference flagged.
struct ComparisonPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var eos: EosClient
    @State private var onlyDifferences = false
    @State private var hideInvalidTargets = false

    var body: some View {
        if let notReady = model.comparisonNotReadyReason {
            Placeholder(text: notReady)
        } else {
            // Hiding invalid cue targets drops QLab cues whose numbers Eos can't fire (like
            // "1A" or "Pre"), from the counts as well as the list.
            let rows = (model.comparisonRows ?? []).filter { !hideInvalidTargets || $0.status != .invalidQLabNumber }
            let shown = onlyDifferences ? rows.filter(\.isMismatch) : rows
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading("CUES")
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Layout.edge)

                    HStack(spacing: 16) {
                        Summary(rows: rows)
                        Spacer()
                        if eos.isLoadingCues {
                            ProgressView().controlSize(.small)
                        }
                        Toggle("Hide Invalid Cue Targets", isOn: $hideInvalidTargets)
                            .help("Hide QLab cues whose numbers Eos can't trigger, like \u{201C}1A\u{201D} or \u{201C}Pre\u{201D}")
                        Toggle("Only Show Differences", isOn: $onlyDifferences)
                    }
                    .frame(height: Layout.controlsRowHeight)
                    .padding(.horizontal, Layout.edge)
                    .padding(.bottom, Layout.rowGap)

                    CueComparisonList(rows: shown, activeEosCues: eos.activeCueByList, runningQLabCueIDs: qlab.runningCueIDs)
                }
                .frame(minWidth: 520)

                ApprovalPanel(changes: model.plannedChanges ?? [])
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ApprovalPanelXKey.self,
                                               value: geometry.frame(in: .named(EosPanelXKey.coordinateSpace)).minX)
                    })
            }
        }
    }

}

/// QLab and Eos cues side by side: QLab's on the left and Eos's on the right, each in its own
/// outlined, tinted panel under its own heading, with the status in a neutral panel between them. Rows are created
/// lazily, so long cue lists stay quick to scroll.
struct CueComparisonList: View {
    let rows: [CueComparisonRow]
    /// The active cue in each Eos cue list (list number → cue number); one per list.
    let activeEosCues: [Int: String]
    /// Every running QLab cue; several can run at once.
    var runningQLabCueIDs: Set<String> = []

    static let numberWidth: CGFloat = 64
    /// Wide enough for the longest status, "Not a Valid Eos Cue #", inside the panel's padding.
    static let statusWidth: CGFloat = 190
    /// Space between the QLab, Status and Eos panels.
    static let bandGap: CGFloat = 14
    static let qlabColor = Color.indigo
    static let eosColor = Color.teal
    /// Neutral, since the status belongs to neither source.
    static let statusColor = Color.gray
    static let cornerRadius: CGFloat = 8

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        CueComparisonRowView(row: row,
                                             isQLabRunning: row.qlab.map { runningQLabCueIDs.contains($0.id) } ?? false,
                                             isEosActive: isEosActive(row),
                                             isStriped: index.isMultiple(of: 2))
                    }
                } header: {
                    CueComparisonHeader()
                }
            }
            // The panels are drawn once behind all the rows, so each reads as one block, and
            // the rows are clipped to them so striped rows don't poke past the rounded corners.
            .background(panels)
            .mask(panelOutlines)
            .padding(.horizontal, Layout.edge)
            .padding(.bottom, Layout.rowGap)
        }
    }

    private var panels: some View {
        HStack(spacing: Self.bandGap) {
            CuePanelShape(color: Self.qlabColor)
            CuePanelShape(color: Self.statusColor).frame(width: Self.statusWidth)
            CuePanelShape(color: Self.eosColor)
                // Tells the Connections section where the Eos panel starts.
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: EosPanelXKey.self,
                                           value: geometry.frame(in: .named(EosPanelXKey.coordinateSpace)).minX)
                })
        }
    }

    private var panelOutlines: some View {
        HStack(spacing: Self.bandGap) {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
            RoundedRectangle(cornerRadius: Self.cornerRadius).frame(width: Self.statusWidth)
            RoundedRectangle(cornerRadius: Self.cornerRadius)
        }
    }

    private func isEosActive(_ row: CueComparisonRow) -> Bool {
        guard let cue = row.eos else { return false }
        return activeEosCues[cue.list] == cue.number
    }
}

/// A source's panel: a lightly tinted, outlined rounded rectangle.
private struct CuePanelShape: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: CueComparisonList.cornerRadius)
            .fill(color.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: CueComparisonList.cornerRadius)
                    .strokeBorder(color.opacity(0.55), lineWidth: 1)
            )
    }
}

/// "QLab" and "Eos" over their own columns. Pinned above the rows while scrolling.
private struct CueComparisonHeader: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: CueComparisonList.bandGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text("QLab").font(.headline).foregroundStyle(CueComparisonList.qlabColor)
                HStack(spacing: CueComparisonRowView.cellGap) {
                    Text("Cue #").frame(width: CueComparisonList.numberWidth, alignment: .leading)
                    Text("Cue Name").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .cueHeaderCell(CueComparisonList.qlabColor)

            VStack(alignment: .leading, spacing: 2) {
                // Plain text colour: grey on the grey header was too faint to read.
                Text("Status").font(.headline).foregroundStyle(.primary)
                // Matches the column-name line under QLab and Eos, so all three headers are level.
                Text(" ").font(.caption)
            }
            .cueHeaderCell(CueComparisonList.statusColor)
            .frame(width: CueComparisonList.statusWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text("Eos").font(.headline).foregroundStyle(CueComparisonList.eosColor)
                HStack(spacing: CueComparisonRowView.cellGap) {
                    Text("Cue #").frame(width: CueComparisonList.numberWidth, alignment: .leading)
                    Text("Cue Label").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .cueHeaderCell(CueComparisonList.eosColor)
        }
        // Opaque, so rows scrolling underneath don't show through.
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// One cue number: the QLab cue on the left, the status, then the Eos cue on the right.
private struct CueComparisonRowView: View {
    let row: CueComparisonRow
    let isQLabRunning: Bool
    let isEosActive: Bool
    let isStriped: Bool

    /// Space between a cue's number and its name, so a cut-off name doesn't run into the next column.
    static let cellGap: CGFloat = 8

    var body: some View {
        HStack(spacing: CueComparisonList.bandGap) {
            HStack(spacing: Self.cellGap) {
                number(row.qlab?.number, isPlaying: isQLabRunning)
                    .frame(width: CueComparisonList.numberWidth, alignment: .leading)
                cell(row.qlab?.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cueRowCell(isStriped: isStriped)

            StatusBadge(status: row.status)
                .cueRowCell(isStriped: isStriped)
                .frame(width: CueComparisonList.statusWidth)

            HStack(spacing: Self.cellGap) {
                number(row.eos?.number, isPlaying: isEosActive)
                    .frame(width: CueComparisonList.numberWidth, alignment: .leading)
                cell(row.eos?.label, color: row.status == .labelDiffers ? .orange : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cueRowCell(isStriped: isStriped)
        }
    }

    /// A cue number, with a green ▶ before it while the cue is running (QLab) or active (Eos).
    private func number(_ text: String?, isPlaying: Bool) -> some View {
        HStack(spacing: 4) {
            if isPlaying {
                Text("▶").foregroundStyle(.green)
            }
            cell(text)
        }
    }

    /// The value, or a dimmed dash when this side has no cue, so a missing cue stands out.
    @ViewBuilder
    private func cell(_ text: String?, color: Color = .primary) -> some View {
        if let text {
            Text(text)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

private extension View {
    /// A row's part inside one panel. Stripes stay inside the panels, so nothing bridges the gaps.
    func cueRowCell(isStriped: Bool) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isStriped ? Color.primary.opacity(0.04) : Color.clear)
    }

    /// A panel's heading: a darker band in the source's colour across the top of the panel.
    func cueHeaderCell(_ color: Color) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // Rounded on top only, so the heading joins the panel below without a notch.
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: CueComparisonList.cornerRadius)
                    Rectangle().frame(height: CueComparisonList.cornerRadius)
                }
                .foregroundStyle(color)
                // Flatten first, so the overlapping shapes don't double the tint.
                .compositingGroup()
                .opacity(0.28)
            )
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
        case .duplicateQLabNumber: return "Another QLab cue number is the same Eos cue number, like 4 and 4.0. Renumber one of them in QLab; nothing will be synced for this number until then."
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
