import Combine
import CueSyncCore
import Foundation

/// Owns the settings, the two connections and the log, and wires them together.
final class AppModel: ObservableObject {
    let settings: AppSettings
    let log: ConnectionLog
    let interfaces: NetworkInterfaceMonitor
    let qlab: QLabClient
    let eos: EosClient
    let actionLog = ActionLog()
    private(set) lazy var changes = ChangeController(
        actionLog: actionLog, settings: settings, eos: eos,
        currentChanges: { [weak self] in self?.plannedChanges }
    )

    private var started = false
    private var interfaceWatch: AnyCancellable?

    init() {
        let settings = AppSettings()
        let log = ConnectionLog()
        let interfaces = NetworkInterfaceMonitor()
        self.settings = settings
        self.log = log
        self.interfaces = interfaces
        self.qlab = QLabClient(log: log)
        self.eos = EosClient(log: log) { name in interfaces.nwInterface(named: name) }
        eos.setMainCueList(settings.eosMainCueList)

        // Fires now with the current list, then whenever interfaces come and go.
        interfaceWatch = interfaces.$interfaces.sink { [weak self] list in
            self?.applyDefaultEosInterface(list)
        }
    }

    /// Until the user picks an interface, use the one with a 10.101.x.x address (or Automatic if none),
    /// and reconnect to Eos when that changes.
    private func applyDefaultEosInterface(_ list: [NetworkInterfaceInfo]) {
        let name = EosDefaults.interface(in: list.map { (name: $0.name, addresses: $0.addresses) }) ?? ""
        if settings.applyDefaultEosInterface(name), started {
            connectEos()
        }
    }

    /// Forgets the interface picked in Settings and goes back to the default.
    func useDefaultEosInterface() {
        settings.clearEosInterfaceChoice()
        applyDefaultEosInterface(interfaces.interfaces)
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        connectQLab()
        connectEos()
    }

    func connectQLab() {
        qlab.start(workspaceID: settings.qlabWorkspaceID, passcode: settings.qlabPasscode)
    }

    func connectEos() {
        let config = EosConnectionConfig(
            host: settings.eosHost,
            framing: settings.eosFraming,
            interfaceName: settings.eosInterfaceName
        )
        eos.start(config: config, cueList: settings.eosCueList)
    }

    /// The QLab cue list the user chose, if it is in the open workspace.
    var selectedQLabCueList: QLabCue? {
        qlab.cueLists.first { $0.id == settings.qlabCueListID }
    }

    /// Every numbered cue in the chosen QLab cue list: the source of truth.
    var qlabNumberedCues: [QLabCue] {
        selectedQLabCueList?.numberedDescendants() ?? []
    }

    /// Why QLab and Eos can't be compared yet, or nil when both sides are loaded.
    /// Comparing early would flag every cue, so the UI shows this instead.
    var comparisonNotReadyReason: String? {
        if settings.eosCueList == nil { return "Choose the Eos cue list to sync in Settings." }
        if selectedQLabCueList == nil {
            return qlab.status == .connected
                ? "Choose the QLab cue list to use in Settings."
                : "Waiting for QLab."
        }
        if eos.status != .connected { return "Waiting for Eos." }
        if !eos.cuesLoaded || eos.cueList != settings.eosCueList {
            return "Reading Eos cue list \(settings.eosCueList ?? 0)…"
        }
        return nil
    }

    /// QLab and Eos cues lined up, or nil when not ready.
    var comparisonRows: [CueComparisonRow]? {
        guard comparisonNotReadyReason == nil else { return nil }
        return CueComparison.compare(qlab: qlabNumberedCues, eos: eos.cues)
    }

    /// The changes Eos needs to match QLab, or nil when not ready.
    var plannedChanges: [EosChange]? {
        guard let rows = comparisonRows, let list = settings.eosCueList else { return nil }
        return EosChange.plan(from: rows, list: list)
    }
}
