import CueSyncCore
import Foundation

/// Owns the settings, the two connections and the log, and wires them together.
final class AppModel: ObservableObject {
    let settings: AppSettings
    let log: ConnectionLog
    let interfaces: NetworkInterfaceMonitor
    let qlab: QLabClient
    let eos: EosClient

    private var started = false

    init() {
        let settings = AppSettings()
        let log = ConnectionLog()
        let interfaces = NetworkInterfaceMonitor()
        self.settings = settings
        self.log = log
        self.interfaces = interfaces
        self.qlab = QLabClient(log: log)
        self.eos = EosClient(log: log) { name in interfaces.nwInterface(named: name) }
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
}
