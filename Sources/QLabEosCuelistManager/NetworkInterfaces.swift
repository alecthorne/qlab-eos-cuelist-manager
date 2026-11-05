import Darwin
import Foundation
import Network

struct NetworkInterfaceInfo: Identifiable, Hashable {
    let name: String
    let addresses: [String]
    var id: String { name }

    var title: String {
        addresses.isEmpty ? name : "\(name) (\(addresses.joined(separator: ", ")))"
    }
}

/// Keeps a live list of network interfaces, so the user can choose the one on the Eos network.
final class NetworkInterfaceMonitor: ObservableObject {
    /// Interfaces that are up and have an IPv4 address, excluding loopback.
    @Published private(set) var interfaces: [NetworkInterfaceInfo] = []

    private let monitor = NWPathMonitor()
    private var nwInterfaces: [NWInterface] = []

    init() {
        interfaces = Self.ipv4Interfaces()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.nwInterfaces = path.availableInterfaces
            self.interfaces = Self.ipv4Interfaces()
        }
        monitor.start(queue: .main)
    }

    deinit {
        monitor.cancel()
    }

    /// The Network.framework interface with this BSD name (e.g. "en0"), if it is available now.
    func nwInterface(named name: String) -> NWInterface? {
        nwInterfaces.first { $0.name == name }
    }

    static func ipv4Interfaces() -> [NetworkInterfaceInfo] {
        var addressesByName: [String: [String]] = [:]
        var order: [String] = []

        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(bitPattern: entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let name = String(cString: entry.ifa_name)
            if addressesByName[name] == nil { order.append(name) }
            addressesByName[name, default: []].append(String(cString: host))
        }
        return order.map { NetworkInterfaceInfo(name: $0, addresses: addressesByName[$0] ?? []) }
    }
}
