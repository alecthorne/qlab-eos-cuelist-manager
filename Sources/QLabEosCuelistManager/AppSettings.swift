import CueSyncCore
import Foundation

/// User settings, saved in UserDefaults.
final class AppSettings: ObservableObject {
    private enum Key {
        static let qlabWorkspaceID = "qlabWorkspaceID"
        static let qlabPasscode = "qlabPasscode"
        static let qlabCueListID = "qlabCueListID"
        static let eosHost = "eosHost"
        static let eosFraming = "eosFraming"
        static let eosInterfaceName = "eosInterfaceName"
        static let eosCueList = "eosCueList"
        static let eosAddTemplate = "eosAddTemplate"
        static let eosUser = "eosUser"
    }

    private let defaults: UserDefaults

    /// QLab workspace unique ID. Empty means "use the only open workspace".
    @Published var qlabWorkspaceID: String { didSet { defaults.set(qlabWorkspaceID, forKey: Key.qlabWorkspaceID) } }
    @Published var qlabPasscode: String { didSet { defaults.set(qlabPasscode, forKey: Key.qlabPasscode) } }
    /// Unique ID of the QLab cue list whose numbered cues are the source of truth.
    @Published var qlabCueListID: String { didSet { defaults.set(qlabCueListID, forKey: Key.qlabCueListID) } }

    @Published var eosHost: String { didSet { defaults.set(eosHost, forKey: Key.eosHost) } }
    @Published var eosFraming: OSCTCPFraming { didSet { defaults.set(eosFraming.rawValue, forKey: Key.eosFraming) } }
    /// BSD name of the interface on the Eos network (e.g. "en7"). Empty means let macOS choose.
    @Published var eosInterfaceName: String { didSet { defaults.set(eosInterfaceName, forKey: Key.eosInterfaceName) } }
    /// The Eos cue list to keep in sync, exactly as typed. Deliberately has no default.
    @Published var eosCueListText: String { didSet { defaults.set(eosCueListText, forKey: Key.eosCueList) } }

    /// Command line used to create a blank cue; {list} and {cue} are filled in.
    @Published var eosAddTemplate: String { didSet { defaults.set(eosAddTemplate, forKey: Key.eosAddTemplate) } }
    /// Optional Eos user number to send commands as. Empty = the console's current user.
    @Published var eosUserText: String { didSet { defaults.set(eosUserText, forKey: Key.eosUser) } }

    /// The Eos user to send as: .some(nil) for the current user, nil if what was typed is invalid.
    var eosUser: Int?? { EosUserNumber.parse(eosUserText) }

    /// The validated Eos cue list number, or nil if the user has not entered a valid one.
    var eosCueList: Int? { EosCueListNumber.parse(eosCueListText) }

    var eosPort: UInt16 { eosFraming == .slip ? 3037 : 3032 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        qlabWorkspaceID = defaults.string(forKey: Key.qlabWorkspaceID) ?? ""
        qlabPasscode = defaults.string(forKey: Key.qlabPasscode) ?? ""
        qlabCueListID = defaults.string(forKey: Key.qlabCueListID) ?? ""
        eosHost = defaults.string(forKey: Key.eosHost) ?? ""
        eosFraming = OSCTCPFraming(rawValue: defaults.string(forKey: Key.eosFraming) ?? "") ?? .slip
        eosInterfaceName = defaults.string(forKey: Key.eosInterfaceName) ?? ""
        eosCueListText = defaults.string(forKey: Key.eosCueList) ?? ""
        eosAddTemplate = defaults.string(forKey: Key.eosAddTemplate) ?? EosCommandBuilder.defaultAddTemplate
        eosUserText = defaults.string(forKey: Key.eosUser) ?? ""
    }
}
