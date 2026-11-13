import Foundation

/// Defaults for the Eos side of Settings.
public enum EosDefaults {
    /// The Eos user that commands are sent as unless Settings says otherwise.
    public static let user = 61

    /// The cue list whose current cue is shown in the main window, unless Settings says otherwise.
    public static let mainCueList = 1

    /// True for an IPv4 address in 10.101.0.0/16, the Eos network.
    public static func isEosNetworkAddress(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        return octets.count == 4 && octets[0] == 10 && octets[1] == 101
    }

    /// The first interface with an address on the Eos network (10.101.x.x), or nil if there is none.
    public static func interface(in interfaces: [(name: String, addresses: [String])]) -> String? {
        interfaces.first { $0.addresses.contains(where: isEosNetworkAddress) }?.name
    }
}
