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
    /// True once connecting has failed `maxRetries` retries in a row. Nothing more is tried
    /// until the connection is started again (e.g. from Settings).
    @Published private(set) var gaveUp = false
    @Published private(set) var version = ""
    @Published private(set) var showName = ""
    /// The cue list being synced. nil until the user chooses one.
    @Published private(set) var cueList: Int?
    /// Cues (and cue parts) in `cueList`, in list order.
    @Published private(set) var cues: [EosCue] = []
    @Published private(set) var isLoadingCues = false
    /// True once the chosen cue list has been read completely at least once.
    @Published private(set) var cuesLoaded = false
    /// The show's cue lists (number → label), or nil until they've been read.
    @Published private(set) var consoleCueLists: [Int: String]?
    /// The active cue in any cue list, as Eos reports it.
    @Published private(set) var activeCue: EosCueRef?
    /// The current cue in `mainCueList`, e.g. "1/5 Lights up 3.0", or "" if not known yet.
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
    private var mainCueList = EosDefaults.mainCueList
    /// The latest /eos/out/active/cue/text, whichever cue list it was for.
    private var lastActiveText = ""
    private var failedAttempts = 0
    private static let maxRetries = 5

    /// While changes are being sent, Eos command line text is written to the connection log
    /// and kept here with the time it arrived, so each failed change can show what Eos said
    /// in response to it.
    private var watchCommandLineUntil = Date.distantPast
    private var lastLoggedCommandLine = ""
    private var commandLineHistory: [(date: Date, text: String)] = []
    private let commandLineHistoryLimit = 200

    private var expectedCueListCount = 0
    private var fetchedCueLists: [Int: (number: Int, label: String)] = [:]

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
        gaveUp = false
        failedAttempts = 0
        version = ""
        showName = ""
        clearCues()
        consoleCueLists = nil
        activeCue = nil
        activeCueText = ""
        lastActiveText = ""
        pendingCueText = ""
    }

    /// Changes which cue list's current cue is shown in `activeCueText`.
    func setMainCueList(_ list: Int) {
        guard list != mainCueList else { return }
        mainCueList = list
        // Only known straight away if Eos's latest active cue is already in that list.
        activeCueText = activeTextList(lastActiveText) == list ? lastActiveText : ""
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

    /// Re-reads which cue lists exist on the console.
    func refreshCueLists() {
        guard status == .connected else { return }
        connection?.send(EosRequest.cueListCount)
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
        guard EosDefaults.isIPv4Address(host) else {
            status = .notConfigured("The Eos IP address isn't valid. Check it in Settings.")
            return
        }

        var interface: NWInterface?
        if !config.interfaceName.isEmpty {
            interface = interfaceLookup(config.interfaceName)
            if interface == nil {
                retryOrGiveUp("The network interface \(config.interfaceName) isn't available. Is it plugged in?")
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
            failedAttempts = 0
            let via = (config?.interfaceName.isEmpty ?? true) ? "" : " via \(config!.interfaceName)"
            log.add("Eos", "Connected to \(config?.host ?? ""):\(config?.port ?? 0)\(via)")
            lastMessageAt = Date()
            connection?.send(EosRequest.version)
            connection?.send(EosRequest.subscribe)
            refreshCues()
            refreshCueLists()
            startHeartbeat()
        case .failed(let failure):
            switch failure {
            case .refused:
                connectionLost("Eos isn't accepting connections. Check the port and Eos's OSC TCP settings.")
            case .unreachable:
                let host = config?.host.trimmingCharacters(in: .whitespaces) ?? ""
                connectionLost("Can't reach Eos at \(host). Check the IP address and network connection.")
            case .closed:
                connectionLost("Eos closed the connection")
            case .other(let detail):
                // The system's wording is only useful when diagnosing, so it goes in the log.
                connectionLost("Can't connect to Eos. Check Connection Log for details.",
                               logged: "Can't connect to Eos: \(detail)")
            }
        }
    }

    /// `logged` replaces `reason` in the Connection Log when it should say more.
    private func connectionLost(_ reason: String, logged: String? = nil) {
        heartbeat?.invalidate()
        heartbeat = nil
        connection?.cancel()
        connection = nil
        isLoadingCues = false
        cuesLoaded = false
        consoleCueLists = nil
        retryOrGiveUp(reason, logged: logged)
    }

    /// Tries again in 3 seconds, unless that would be more than `maxRetries` retries in a row.
    private func retryOrGiveUp(_ reason: String, logged: String? = nil) {
        // Only log a reason when it changes, so retries don't flood the log.
        let isNewReason = status != .error(reason)
        status = .error(reason)
        failedAttempts += 1
        if failedAttempts > Self.maxRetries {
            gaveUp = true
            log.add("Eos", logged ?? reason, then: "Stopped trying after \(Self.maxRetries) retries.")
            return
        }
        if isNewReason {
            log.addRetrying("Eos", logged ?? reason)
        }
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
                self.connectionLost("Eos stopped responding")
            } else {
                self.connection?.send(EosRequest.ping)
            }
        }
    }

    // MARK: - Messages

    /// The cue list active cue text is for: from the text itself, or else from the
    /// /eos/out/active/cue/<list>/<cue> message that comes with it.
    private func activeTextList(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        return EosActiveCueText.list(text) ?? activeCue?.list
    }

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
        case .cueListsChanged:
            scheduleRefresh()
        case .cueListCount(let count):
            expectedCueListCount = count
            fetchedCueLists = [:]
            if count == 0 {
                consoleCueLists = [:]
            } else {
                for index in 0..<count {
                    connection?.send(EosRequest.cueList(index: index))
                }
            }
        case .cueList(let number, let index, let label):
            guard index < expectedCueListCount else { return }
            fetchedCueLists[index] = (number, label)
            if fetchedCueLists.count >= expectedCueListCount {
                consoleCueLists = Dictionary(fetchedCueLists.values.map { ($0.number, $0.label) },
                                             uniquingKeysWith: { first, _ in first })
            }
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
            let wasMain = activeTextList(lastActiveText) == mainCueList
            lastActiveText = text
            if text.isEmpty {
                activeCue = nil
                if wasMain { activeCueText = "" }
            } else if activeTextList(text) == mainCueList {
                activeCueText = text
            }
        case .cueFired(let list, let number, let label):
            // Eos's active cue may follow another list, so fire events keep the main list current.
            // Skipped when the active cue text (which also has the time) already shows this cue.
            let prefix = "\(list)/\(number)"
            guard list == mainCueList,
                  activeCueText != prefix, !activeCueText.hasPrefix(prefix + " ") else { return }
            activeCueText = label.isEmpty ? prefix : prefix + " " + label
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
        let work = DispatchWorkItem { [weak self] in
            self?.refreshCues()
            self?.refreshCueLists()
        }
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
