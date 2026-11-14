import AppKit
import CueSyncCore
import UniformTypeIdentifiers

/// A printable list of QLab cues: the workspace and cue list names at the top, then one
/// "• number - name" line per cue. Pages after the first get a smaller one-line header, and
/// every page has the export date and "Page X of Y" at the bottom.
struct CueListPDF {
    let workspaceName: String
    let cueListName: String
    let cues: [(number: String, name: String)]
    var date = Date()
    /// The paper size the Mac is set up for (Letter or A4, usually).
    var paperSize = NSPrintInfo.shared.paperSize

    private let margin: CGFloat = 54
    private let titleFont = NSFont.boldSystemFont(ofSize: 18)
    private let cueListFont = NSFont.systemFont(ofSize: 13)
    private let smallHeaderFont = NSFont.systemFont(ofSize: 9)
    private let smallHeaderBoldFont = NSFont.boldSystemFont(ofSize: 9)
    private let cueFont = NSFont.systemFont(ofSize: 11)
    private let footerFont = NSFont.systemFont(ofSize: 9)
    /// Space between cue lines.
    private let cueSpacing: CGFloat = 4

    private var contentWidth: CGFloat { paperSize.width - margin * 2 }

    /// The finished PDF, or nil if it couldn't be drawn.
    func data() -> Data? {
        let lines = cues.map(cueText)
        let pages = paginate(lines)

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        let info = [
            kCGPDFContextTitle: "\(workspaceName) - \(cueListName)",
            kCGPDFContextCreator: "QLab → Eos CueSync",
        ] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else { return nil }

        for (pageIndex, lineIndices) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            // Draw top-down, like a page is read.
            context.translateBy(x: 0, y: paperSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            var y = drawHeader(onFirstPage: pageIndex == 0)
            if cues.isEmpty {
                draw(NSAttributedString(string: "This cue list has no numbered cues.",
                                        attributes: attributes(font: cueFont)), at: y)
            }
            for index in lineIndices {
                y += draw(lines[index], at: y) + cueSpacing
            }
            drawFooter(page: pageIndex + 1, of: pages.count)

            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: - Layout

    /// Splits the cue lines into pages: each page holds the line indices that fit on it.
    private func paginate(_ lines: [NSAttributedString]) -> [[Int]] {
        var pages: [[Int]] = [[]]
        var y = margin + headerHeight(onFirstPage: true)
        for (index, line) in lines.enumerated() {
            let height = self.height(of: line)
            if y + height > bodyBottom, !(pages.last ?? []).isEmpty {
                pages.append([])
                y = margin + headerHeight(onFirstPage: false)
            }
            pages[pages.count - 1].append(index)
            y += height + cueSpacing
        }
        return pages
    }

    /// Where cue lines must stop, leaving the bottom margin for the footer.
    private var bodyBottom: CGFloat { paperSize.height - margin }

    private func headerHeight(onFirstPage: Bool) -> CGFloat {
        if onFirstPage {
            return height(of: title) + 4 + height(of: cueListTitle) + ruleGap * 2 + 14
        }
        return height(of: smallHeader) + ruleGap * 2 + 10
    }

    private let ruleGap: CGFloat = 8

    // MARK: - Drawing

    /// Draws the page header and returns where the cue lines start.
    private func drawHeader(onFirstPage: Bool) -> CGFloat {
        var y = margin
        if onFirstPage {
            y += draw(title, at: y) + 4
            y += draw(cueListTitle, at: y) + ruleGap
            drawRule(at: y)
            return y + ruleGap + 14
        }
        y += draw(smallHeader, at: y) + ruleGap
        drawRule(at: y)
        return y + ruleGap + 10
    }

    private func drawFooter(page: Int, of pageCount: Int) {
        let y = paperSize.height - margin + 18
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        draw(NSAttributedString(string: "Exported \(formatter.string(from: date))",
                                attributes: attributes(font: footerFont)), at: y)
        draw(NSAttributedString(string: "Page \(page) of \(pageCount)",
                                attributes: attributes(font: footerFont, alignment: .right)), at: y)
    }

    private func drawRule(at y: CGFloat) {
        NSColor(white: 0.7, alpha: 1).setFill()
        NSRect(x: margin, y: y, width: contentWidth, height: 0.5).fill()
    }

    /// Draws `text` across the content width at `y` and returns its height.
    @discardableResult
    private func draw(_ text: NSAttributedString, at y: CGFloat) -> CGFloat {
        let height = self.height(of: text)
        text.draw(with: NSRect(x: margin, y: y, width: contentWidth, height: height),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        return height
    }

    private func height(of text: NSAttributedString) -> CGFloat {
        ceil(text.boundingRect(with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    // MARK: - Text

    private var title: NSAttributedString {
        NSAttributedString(string: workspaceName, attributes: attributes(font: titleFont))
    }

    private var cueListTitle: NSAttributedString {
        NSAttributedString(string: cueListName, attributes: attributes(font: cueListFont))
    }

    /// "Hamlet  Main Cue List" in small type, for pages after the first.
    private var smallHeader: NSAttributedString {
        let header = NSMutableAttributedString(string: workspaceName,
                                               attributes: attributes(font: smallHeaderBoldFont))
        header.append(NSAttributedString(string: "  " + cueListName,
                                         attributes: attributes(font: smallHeaderFont)))
        return header
    }

    /// One cue's line. If the name wraps, later lines start under the name, not the bullet.
    private func cueText(_ cue: (number: String, name: String)) -> NSAttributedString {
        let prefix = CueSheet.prefix(number: cue.number)
        let prefixWidth = NSAttributedString(string: prefix, attributes: [.font: cueFont]).size().width
        var attributes = attributes(font: cueFont)
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = ceil(prefixWidth)
        attributes[.paragraphStyle] = paragraph
        return NSAttributedString(string: CueSheet.line(number: cue.number, name: cue.name), attributes: attributes)
    }

    /// Always black, so the PDF looks the same whether the app is in light or dark mode.
    private func attributes(font: NSFont, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        return [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]
    }
}

/// Saving the chosen QLab cue list as a PDF, from the File menu or the toolbar.
enum CueListExport {
    /// True once a QLab workspace is open and the chosen cue list is in it.
    static func isAvailable(_ model: AppModel) -> Bool {
        model.qlab.connectedWorkspace != nil && model.selectedQLabCueList != nil
    }

    static func run(_ model: AppModel) {
        guard let workspace = model.qlab.connectedWorkspace, let list = model.selectedQLabCueList else { return }
        let pdf = CueListPDF(
            workspaceName: workspace.displayName,
            cueListName: list.displayName,
            cues: model.qlabNumberedCues.map { (number: $0.number, name: $0.displayName) }
        )

        let panel = NSSavePanel()
        panel.title = "Export Cue List as PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = CueSheet.fileName(workspace: workspace.displayName, cueList: list.displayName)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            guard let data = pdf.data() else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't export the cue list."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
