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
        static let eosMainCueList = "eosMainCueList"
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
    /// Until the user picks one, this follows the default (see `applyDefaultEosInterface`) and isn't saved.
    @Published var eosInterfaceName: String {
        didSet {
            guard !applyingDefaultInterface else { return }
            defaults.set(eosInterfaceName, forKey: Key.eosInterfaceName)
            eosInterfaceChosen = true
        }
    }
    /// True once the user has picked an interface in Settings (including Automatic).
    @Published private(set) var eosInterfaceChosen: Bool
    private var applyingDefaultInterface = false
    /// The Eos cue list to keep in sync, exactly as typed. Deliberately has no default.
    @Published var eosCueListText: String { didSet { defaults.set(eosCueListText, forKey: Key.eosCueList) } }

    /// Eos user number to send commands as (default 61). Empty = the console's current user.
    @Published var eosUserText: String { didSet { defaults.set(eosUserText, forKey: Key.eosUser) } }

    /// The Eos user to send as: .some(nil) for the current user, nil if what was typed is invalid.
    var eosUser: Int?? { EosUserNumber.parse(eosUserText) }

    /// The cue list whose current cue is shown in the main window (1 to 999). Settings only
    /// saves valid numbers here.
    @Published var eosMainCueList: Int { didSet { defaults.set(eosMainCueList, forKey: Key.eosMainCueList) } }

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
        eosInterfaceChosen = defaults.object(forKey: Key.eosInterfaceName) != nil
        eosCueListText = defaults.string(forKey: Key.eosCueList) ?? ""
        // The add-cue command used to be a setting; it's fixed now, so drop any saved value.
        defaults.removeObject(forKey: Key.eosAddTemplate)
        eosUserText = defaults.string(forKey: Key.eosUser) ?? String(EosDefaults.user)
        eosMainCueList = EosCueListNumber.parse(defaults.string(forKey: Key.eosMainCueList) ?? "") ?? EosDefaults.mainCueList
    }

    /// Uses `name` as the Eos interface if the user hasn't picked one. Returns true if it changed.
    /// Not saved, so the default keeps following whichever interface is on 10.101.x.x.
    @discardableResult
    func applyDefaultEosInterface(_ name: String) -> Bool {
        guard !eosInterfaceChosen, name != eosInterfaceName else { return false }
        applyingDefaultInterface = true
        eosInterfaceName = name
        applyingDefaultInterface = false
        return true
    }

    /// Forgets the user's interface choice, so the default applies again.
    func clearEosInterfaceChoice() {
        defaults.removeObject(forKey: Key.eosInterfaceName)
        eosInterfaceChosen = false
    }
}
