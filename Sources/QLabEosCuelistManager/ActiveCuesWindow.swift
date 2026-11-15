import AppKit
import SwiftUI

/// The floating Active Eos Cues window, opened by clicking the Active Eos Cues box in the main window.
/// It stays above other apps' windows (QLab included) so the active cues are always in view.
/// The window has no frame of its own: the green box, drawn over a dark translucent background
/// like QLab's Override Controls window, is the window's edge.
@MainActor
final class ActiveCuesWindowController: NSObject, NSWindowDelegate {
    static let shared = ActiveCuesWindowController()

    private var panel: NSPanel?
    /// The smallest the window can be, measured from its content.
    private var minimumSize = NSSize.zero
    /// The tallest the window can be: enough for all the content at full size.
    private var maximumHeight = CGFloat.greatestFiniteMagnitude

    /// True while the floating window is on screen.
    var isOpen: Bool { panel?.isVisible ?? false }

    func show(model: AppModel) {
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let panel = BorderlessPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 230),
                                    styleMask: [.borderless, .resizable, .nonactivatingPanel],
                                    backing: .buffered,
                                    defer: false)
        panel.title = "Active Eos Cues"
        panel.isFloatingPanel = true
        panel.level = .floating
        // Stays up while another app (like QLab) is in front, and on every Space.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        // Clear, so only the rounded box shows; the shadow follows its shape.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        let hostingView = NSHostingView(rootView: ActiveCuesWindowView { [weak panel] in panel?.close() }
            .environmentObjects(model))
        // The window's minimum size is set below; otherwise the hosting view would replace it
        // with its own.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        let sizes = contentSizes(model: model)
        // A borderless window ignores contentMinSize when resized by hand, so the limits are
        // enforced in windowWillResize instead.
        minimumSize = sizes.minimum
        maximumHeight = sizes.initial.height
        panel.contentMinSize = sizes.minimum
        panel.delegate = self
        // Reopens where it was last left; the first time, centered and just tall enough for
        // the content at full size.
        if !panel.setFrameUsingName("ActiveCuesWindow") {
            panel.setContentSize(sizes.initial)
            panel.center()
        }
        panel.setFrameAutosaveName("ActiveCuesWindow")
        // A saved size from before these limits existed could be outside them.
        let size = panel.contentRect(forFrameRect: panel.frame).size
        let allowed = allowedSize(size)
        if allowed != size {
            panel.setContentSize(allowed)
        }
        return panel
    }

    /// If the floating window was the last one open (the main window was closed while it was
    /// up), closing it quits the app, as closing the last window does otherwise.
    func windowWillClose(_ notification: Notification) {
        let othersOpen = NSApp.windows.contains { $0 !== panel && $0.isVisible }
        if !othersOpen {
            NSApp.terminate(nil)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Borderless, so the frame and the content are the same size.
        allowedSize(frameSize)
    }

    /// `size` kept within the minimum size and the maximum height.
    private func allowedSize(_ size: NSSize) -> NSSize {
        NSSize(width: max(size.width, minimumSize.width),
               height: min(max(size.height, minimumSize.height), maximumHeight))
    }

    /// The window's minimum size, measured from its content: as narrow as the whole heading
    /// allows, and as short as the heading and both cue lines allow with the cue text shrunk
    /// as far as it goes. Also the first-time size: 440 wide and tall enough for full-size text.
    private func contentSizes(model: AppModel) -> (minimum: NSSize, initial: NSSize) {
        let content = NSHostingController(rootView: ActiveCuesContent().environmentObjects(model))
        let unlimited = CGFloat.greatestFiniteMagnitude
        let minWidth = ceil(content.sizeThatFits(in: CGSize(width: 0, height: unlimited)).width)
        let minHeight = ceil(content.sizeThatFits(in: CGSize(width: minWidth, height: 0)).height)
        let width = max(440, minWidth)
        let height = ceil(content.sizeThatFits(in: CGSize(width: width, height: unlimited)).height)
        return (NSSize(width: minWidth, height: minHeight), NSSize(width: width, height: max(height, minHeight)))
    }
}

/// A borderless panel can't become key by default, which would stop its close button and
/// Escape from working.
private final class BorderlessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The floating window: the content in the green box, with a close button in the corner.
private struct ActiveCuesWindowView: View {
    let close: () -> Void

    var body: some View {
        ActiveCuesContent()
            // Clicks on the text fall through to the drag area behind, so the window can be
            // moved by dragging anywhere but the close button.
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .padding(8)
            }
            .background(WindowDragArea())
            .activeCuesBox()
            .background(HUDBackground(cornerRadius: CueComparisonList.cornerRadius))
    }
}

/// The heading, then each cuelist's active cue in large type, in sections split by a divider.
/// Also measured on its own to work out the window's minimum size.
private struct ActiveCuesContent: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eos: EosClient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVE EOS CUES")
                .font(.title3.bold())
                .fixedSize()
                // Clear of the close button on the left, and balanced on the right.
                .padding(.horizontal, Self.closeButtonClearance)
                .frame(maxWidth: .infinity)
            // Laid out even when hidden, so the window keeps the same minimum size whether or
            // not Eos is connected.
            VStack(alignment: .leading, spacing: 10) {
                cue(label: "Main Cuelist", value: ActiveCues.mainCueText(eos: eos))
                Divider()
                cue(label: "Video Cuelist", value: ActiveCues.videoCueText(settings: settings, eos: eos))
            }
            .opacity(eos.status == .connected ? 1 : 0)
            .overlay {
                if eos.status != .connected {
                    Text("Eos Not Connected")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    /// Room for the close button (8 + 13 + 8 points from the window's edge) plus a gap, so the
    /// heading never runs under it.
    private static let closeButtonClearance: CGFloat = 20

    private func cue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.title3)
                .lineLimit(1)
            Text(value.isEmpty ? "None" : value)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(value.isEmpty ? Color.secondary : Color.green)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .truncationMode(.tail)
        }
    }
}

/// Moves the window when dragged, since a borderless window has no title bar to drag.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// The dark, translucent background of a HUD window, with rounded corners.
private struct HUDBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Active cue text shared by the main window's Active Eos Cues box and the floating window.
enum ActiveCues {
    /// Goes between a cue's number and its label, e.g. "1/5 - Lights up".
    static let separator = " - "

    /// The main cuelist's active cue, e.g. "1/5 - Lights up 3.0". Eos sends it as
    /// "1/5 Lights up 3.0", so the separator replaces the space after the cue number.
    /// "" if nothing is active.
    @MainActor
    static func mainCueText(eos: EosClient) -> String {
        let parts = eos.activeCueText.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return eos.activeCueText }
        return parts[0] + separator + parts[1]
    }

    /// The video cuelist's active cue in the same form as the main cuelist's, e.g.
    /// "3/7 - Also six", with the label from the synced cues. "" if nothing is active.
    @MainActor
    static func videoCueText(settings: AppSettings, eos: EosClient) -> String {
        guard let list = settings.eosCueList, let number = eos.activeCueByList[list] else { return "" }
        let label = eos.cues.first { $0.list == list && $0.number == number && $0.part == 0 }?.label ?? ""
        return label.isEmpty ? "\(list)/\(number)" : "\(list)/\(number)\(separator)\(label)"
    }
}

extension View {
    /// The green rounded box behind the active cues, in the main window and the floating
    /// window: tinted like the QLab and Eos panels in the cue list, with a solid border.
    func activeCuesBox() -> some View {
        let shape = RoundedRectangle(cornerRadius: CueComparisonList.cornerRadius)
        return self
            .background(shape.fill(Color.green.opacity(0.12)))
            .overlay(shape.strokeBorder(Color.green, lineWidth: 1))
            .contentShape(shape)
    }
}
