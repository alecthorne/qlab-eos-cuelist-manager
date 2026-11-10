import CueSyncCore
import Foundation
import Network

struct EosConnectionConfig: Equatable {
    var host: String
    var framing: OSCTCPFraming
    /// BSD interface name; empty = let macOS choose.
    var interfaceName: String

    var port: UInt16 { framing == .slip ? 3037 : 3032 }
}

struct EosCueRef: Equatable {
    let list: Int
    let number: String
}

/// Talks to an Eos console (or Nomad) over OSC/TCP, on the network interface the user chose.
final class EosClient: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case notConfigured(String)
        case connecting
        case connected
        case error(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var version = ""
    @Published private(set) var showName = ""
    /// The cue list being synced. nil until the user chooses one.
    @Published private(set) var cueList: Int?
    /// Cues (and cue parts) in `cueList`, in list order.
    @Published private(set) var cues: [EosCue] = []
    @Published private(set) var isLoadingCues = false
    /// True once the chosen cue list has been read completely at least once.
    @Published private(set) var cuesLoaded = false
    @Published private(set) var activeCue: EosCueRef?
    @Published private(set) var activeCueText = ""
    @Published private(set) var pendingCueText = ""

    private let log: ConnectionLog
    private let interfaceLookup: (String) -> NWInterface?
    private var config: EosConnectionConfig?
    private var connection: OSCTCPConnection?
    private var reconnectWork: DispatchWorkItem?
    private var refreshWork: DispatchWorkItem?
    private var heartbeat: Timer?
    private var lastMessageAt = Date()

    /// While changes are being sent, Eos command line text is written to the connection log
    /// and kept here with the time it arrived, so each failed change can show what Eos said
    /// in response to it.
    private var watchCommandLineUntil = Date.distantPast
    private var lastLoggedCommandLine = ""
    private var commandLineHistory: [(date: Date, text: String)] = []
    private let commandLineHistoryLimit = 200

    private var expectedCueCount = 0
    /// Replies so far, keyed by position and part so that the parts of a multipart cue
    /// never overwrite each other or the cue itself.
    private var fetchedCues: [EosCueSlot: EosCue] = [:]
    /// Positions (0..<expectedCueCount) that Eos has replied for.
    private var fetchedIndices: Set<Int> = []

    init(log: ConnectionLog, interfaceLookup: @escaping (String) -> NWInterface?) {
        self.log = log
        self.interfaceLookup = interfaceLookup
    }

    func start(config: EosConnectionConfig, cueList: Int?) {
        stop()
        self.config = config
        self.cueList = cueList
        open()
    }

    func stop() {
        reconnectWork?.cancel()
        refreshWork?.cancel()
        heartbeat?.invalidate()
        heartbeat = nil
        connection?.cancel()
        connection = nil
        config = nil
        status = .disconnected
        version = ""
        showName = ""
        clearCues()
        activeCue = nil
        activeCueText = ""
        pendingCueText = ""
    }

    /// Changes which cue list is synced, and re-reads it.
    func setCueList(_ list: Int?) {
        guard list != cueList else { return }
        cueList = list
        clearCues()
        refreshCues()
    }

    /// Re-reads every cue in the chosen cue list.
    func refreshCues() {
        guard status == .connected, let cueList else { return }
        isLoadingCues = true
        connection?.send(EosRequest.cueCount(list: cueList))
    }

    /// Sends command lines to Eos, in order. Returns false if not connected.
    @discardableResult
    func send(_ commands: [EosCommand], user: Int?) -> Bool {
        guard status == .connected, let connection else { return false }
        watchCommandLineUntil = max(watchCommandLineUntil, Date().addingTimeInterval(10))
        lastLoggedCommandLine = ""
        for command in commands {
            let message = command.message(user: user)
            let arguments = message.arguments.compactMap(\.stringValue).map { "“" + $0 + "”" }
            log.add("Eos", "Sent " + ([message.address] + arguments).joined(separator: " "))
            connection.send(message)
        }
        return true
    }

    /// Command line texts Eos reported from `start` up to (not including) `end`, oldest first.
    /// `end` nil means up to now.
    func commandLineTexts(from start: Date, to end: Date?) -> [String] {
        commandLineHistory
            .filter { entry in entry.date >= start && (end.map { entry.date < $0 } ?? true) }
            .map(\.text)
    }

    // MARK: - Connection

    private func open() {
        guard let config else { return }
        let host = config.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            status = .notConfigured("Enter the Eos console's IP address in Settings")
            return
        }

        var interface: NWInterface?
        if !config.interfaceName.isEmpty {
            interface = interfaceLookup(config.interfaceName)
            if interface == nil {
                let reason = "Network interface \(config.interfaceName) is not available"
                if status != .error(reason) { log.add("Eos", reason + ". Retrying.") }
                status = .error(reason)
                scheduleReconnect()
                return
            }
        }

        let connection = OSCTCPConnection(host: host, port: config.port, framing: config.framing, requiredInterface: interface)
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
            status = .connected
            let via = (config?.interfaceName.isEmpty ?? true) ? "" : " via \(config!.interfaceName)"
            log.add("Eos", "Connected to \(config?.host ?? ""):\(config?.port ?? 0)\(via)")
            lastMessageAt = Date()
            connection?.send(EosRequest.version)
            connection?.send(EosRequest.subscribe)
            refreshCues()
            startHeartbeat()
        case .failed(let reason):
            connectionLost(reason)
        }
    }

    private func connectionLost(_ reason: String) {
        if status != .error(reason) {
            log.add("Eos", "Not connected: \(reason). Retrying.")
        }
        heartbeat?.invalidate()
        heartbeat = nil
        connection?.cancel()
        connection = nil
        status = .error(reason)
        isLoadingCues = false
        cuesLoaded = false
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connection == nil, self.config != nil else { return }
            self.open()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Pings Eos every 5 seconds, and treats 15 seconds of silence as a dropped connection
    /// (a pulled cable doesn't always close a TCP connection).
    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastMessageAt) > 15 {
                self.connectionLost("No reply from Eos for 15 seconds")
            } else {
                self.connection?.send(EosRequest.ping)
            }
        }
    }

    // MARK: - Messages

    private func handle(_ message: OSCMessage) {
        lastMessageAt = Date()
        switch EosOutput.parse(message) {
        case .version(let value):
            version = value
        case .showName(let value):
            showName = value
        case .showReset:
            log.add("Eos", "Show loaded or cleared. Re-reading cues.")
            scheduleRefresh()
        case .cueListChanged(let list):
            if list == cueList { scheduleRefresh() }
        case .cueCount(let list, let count):
            guard list == cueList else { return }
            expectedCueCount = count
            fetchedCues = [:]
            fetchedIndices = []
            if count == 0 {
                cues = []
                isLoadingCues = false
                cuesLoaded = true
            } else {
                for index in 0..<count {
                    connection?.send(EosRequest.cue(list: list, index: index))
                }
            }
        case .cue(let cue):
            guard cue.list == cueList, isLoadingCues else { return }
            fetchedCues[EosCueSlot(index: cue.index, part: cue.part)] = cue
            fetchedIndices.insert(cue.index)
            if fetchedIndices.count >= expectedCueCount {
                cues = fetchedCues.values.sorted { ($0.index, $0.part) < ($1.index, $1.part) }
                isLoadingCues = false
                cuesLoaded = true
            }
        case .activeCue(let list, let number, _):
            activeCue = EosCueRef(list: list, number: number)
        case .activeCueText(let text):
            activeCueText = text
            if text.isEmpty { activeCue = nil }
        case .pendingCueText(let text):
            pendingCueText = text
        case .commandLine(let user, let text):
            guard Date() < watchCommandLineUntil, !text.isEmpty, text != lastLoggedCommandLine else { return }
            lastLoggedCommandLine = text
            commandLineHistory.append((Date(), text))
            if commandLineHistory.count > commandLineHistoryLimit {
                commandLineHistory.removeFirst(commandLineHistory.count - commandLineHistoryLimit)
            }
            let who = user.map { "user \($0) " } ?? ""
            log.add("Eos", "Eos \(who)command line: \(text)")
        case .pendingCue, .ping, .other:
            break
        }
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshCues() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func clearCues() {
        cues = []
        fetchedCues = [:]
        fetchedIndices = []
        expectedCueCount = 0
        isLoadingCues = false
        cuesLoaded = false
    }
}

private struct EosCueSlot: Hashable {
    let index: Int
    let part: Int
}
