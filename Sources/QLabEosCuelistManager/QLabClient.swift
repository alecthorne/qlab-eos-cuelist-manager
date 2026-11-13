import CueSyncCore
import Foundation

/// Talks to QLab 5 on this Mac over OSC/TCP (port 53000, SLIP framing).
final class QLabClient: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case connecting
        /// Connected to QLab, but no workspace chosen (or the chosen one isn't open).
        case waitingForWorkspace(String)
        case connected
        case error(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var workspaces: [QLabWorkspace] = []
    @Published private(set) var connectedWorkspace: QLabWorkspace?
    /// Top-level cue lists of the connected workspace, with their cues.
    @Published private(set) var cueLists: [QLabCue] = []

    private let log: ConnectionLog
    private var connection: OSCTCPConnection?
    private var desiredWorkspaceID = ""
    private var passcode = ""
    private var pendingWorkspaceID: String?
    private var reconnectWork: DispatchWorkItem?
    private var refreshWork: DispatchWorkItem?
    private var pollTimer: Timer?

    static let host = "127.0.0.1"
    static let port: UInt16 = 53000

    init(log: ConnectionLog) {
        self.log = log
    }

    /// (Re)connects to QLab and opens the given workspace ("" = the only open one).
    func start(workspaceID: String, passcode: String) {
        desiredWorkspaceID = workspaceID
        self.passcode = passcode
        stop()
        open()
    }

    func stop() {
        reconnectWork?.cancel()
        refreshWork?.cancel()
        pollTimer?.invalidate()
        pollTimer = nil
        connection?.cancel()
        connection = nil
        pendingWorkspaceID = nil
        connectedWorkspace = nil
        cueLists = []
        status = .disconnected
    }

    /// Re-reads the cue lists of the connected workspace.
    func refreshCueLists() {
        guard let id = connectedWorkspace?.id else { return }
        connection?.send(OSCMessage("/workspace/\(id)/cueLists"))
    }

    // MARK: - Connection

    private func open() {
        let connection = OSCTCPConnection(host: Self.host, port: Self.port, framing: .slip)
        connection.onStateChange = { [weak self] state in self?.handle(state) }
        connection.onMessage = { [weak self] message in self?.handle(message) }
        self.connection = connection
        connection.start()
    }

    private func handle(_ state: OSCTCPConnection.State) {
        switch state {
        case .connecting:
            status = .connecting
        case .ready:
            log.add("QLab", "Connected to QLab on port \(Self.port)")
            requestWorkspaces()
            // Keep the workspace list fresh, so opening or closing a workspace is noticed.
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.requestWorkspaces()
            }
        case .failed(let failure):
            let reason: String
            let logged: String
            switch failure {
            case .refused, .unreachable:
                reason = "Can't find QLab. Is it open on this Mac?"
                logged = reason
            case .closed:
                reason = "QLab closed the connection"
                logged = reason
            case .other(let detail):
                // The system's wording is only useful when diagnosing, so it goes in the log.
                reason = "Can't connect to QLab. Check Connection Log for details."
                logged = "Can't connect to QLab: \(detail)"
            }
            if status != .error(reason) {
                log.addRetrying("QLab", logged)
            }
            pollTimer?.invalidate()
            pollTimer = nil
            connection = nil
            pendingWorkspaceID = nil
            connectedWorkspace = nil
            cueLists = []
            status = .error(reason)
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connection == nil else { return }
            self.open()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func requestWorkspaces() {
        connection?.send(OSCMessage("/workspaces"))
    }

    // MARK: - Messages

    private func handle(_ message: OSCMessage) {
        if message.address.hasPrefix("/update/") {
            handleUpdate(message)
            return
        }
        guard let reply = QLabReply.parse(message) else { return }

        if reply.address == "/workspaces" {
            workspaces = QLabWorkspace.parseList(reply.data)
            chooseWorkspace()
        } else if reply.address.hasSuffix("/connect"), let id = reply.workspaceID ?? pendingWorkspaceID {
            handleConnectReply(reply, workspaceID: id)
        } else if reply.address.hasSuffix("/cueLists") {
            guard reply.workspaceID == nil || reply.workspaceID == connectedWorkspace?.id else { return }
            if reply.isOK {
                cueLists = QLabCue.parseList(reply.data)
            } else {
                log.add("QLab", "Could not read cue lists (\(reply.status)). Check the workspace's OSC access settings.")
            }
        } else if reply.address.hasSuffix("/updates"), !reply.isOK {
            // QLab only answers /updates when it refuses; a refusal means edits stop arriving silently.
            guard reply.workspaceID == nil || reply.workspaceID == connectedWorkspace?.id else { return }
            log.add("QLab", "QLab refused live updates (\(reply.status)). Changes in QLab won't appear until you "
                + "click Refresh. In QLab, check Workspace Settings → Network → OSC Access: the passcode needs View.")
        }
    }

    private func chooseWorkspace() {
        let target: QLabWorkspace?
        if !desiredWorkspaceID.isEmpty {
            target = workspaces.first { $0.id == desiredWorkspaceID }
        } else if workspaces.count == 1 {
            target = workspaces.first
        } else {
            target = nil
        }

        guard let target else {
            if connectedWorkspace != nil {
                log.add("QLab", "Workspace \(connectedWorkspace?.displayName ?? "") is no longer open")
            }
            connectedWorkspace = nil
            cueLists = []
            pendingWorkspaceID = nil
            let reason: String
            if workspaces.isEmpty {
                reason = "No QLab workspace is open"
            } else if desiredWorkspaceID.isEmpty {
                reason = "Several workspaces are open. Choose one in Settings."
            } else {
                reason = "The chosen workspace is not open"
            }
            status = .waitingForWorkspace(reason)
            return
        }

        if connectedWorkspace?.id == target.id || pendingWorkspaceID == target.id { return }
        pendingWorkspaceID = target.id
        let args: [OSCArgument] = passcode.isEmpty ? [] : [.string(passcode)]
        connection?.send(OSCMessage("/workspace/\(target.id)/connect", args))
    }

    private func handleConnectReply(_ reply: QLabReply, workspaceID: String) {
        guard workspaceID == pendingWorkspaceID else { return }
        pendingWorkspaceID = nil
        let result = reply.data as? String ?? ""
        guard reply.isOK, result.hasPrefix("ok") else {
            let reason = result == "badpass" ? "The QLab passcode is wrong. Check it in Settings." : "QLab refused the connection (\(result.isEmpty ? reply.status : result))"
            log.add("QLab", reason)
            status = .error(reason)
            return
        }
        let workspace = workspaces.first { $0.id == workspaceID } ?? QLabWorkspace(id: workspaceID, displayName: workspaceID)
        connectedWorkspace = workspace
        status = .connected
        log.add("QLab", "Opened workspace \(workspace.displayName)")
        if let permissions = QLabReply.connectPermissions(result), !permissions.contains("view") {
            log.add("QLab", "QLab connected without View permission, so cue lists and live updates will be refused. "
                + "Enter a passcode with View permission in Settings, or allow View without a passcode in QLab's "
                + "Workspace Settings → Network → OSC Access.")
        }
        connection?.send(OSCMessage("/workspace/\(workspaceID)/updates", [.int(1)]))
        refreshCueLists()
    }

    private func handleUpdate(_ message: OSCMessage) {
        let parts = message.addressComponents
        // /update/workspace/{id}/...
        guard parts.count >= 3, parts[1] == "workspace", parts[2] == connectedWorkspace?.id else { return }
        if parts.last == "disconnect" {
            log.add("QLab", "QLab asked us to disconnect. Reconnecting.")
            start(workspaceID: desiredWorkspaceID, passcode: passcode)
            return
        }
        // Playhead moves don't change cue numbers or names.
        if parts.last == "playbackPosition" || parts.dropLast().last == "playbackPosition" { return }
        scheduleRefresh()
    }

    /// QLab can send many updates at once; wait for them to settle, then re-read once.
    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshCueLists() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
