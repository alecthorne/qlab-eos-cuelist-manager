import CueSyncCore
import Foundation
import Network

/// One OSC-over-TCP connection. Callbacks are always delivered on the main queue.
final class OSCTCPConnection {
    enum State: Equatable {
        case connecting
        case ready
        case failed(Failure)
    }

    /// Why a connection ended, so QLab and Eos can each explain it in their own words.
    enum Failure: Equatable {
        /// The machine answered but nothing is listening on the port.
        case refused
        /// Nothing answered at the address (wrong IP, cable unplugged, timed out).
        case unreachable
        /// The other end closed the connection.
        case closed
        /// Anything else, with the system's short reason for the Connection Log.
        case other(String)
    }

    var onStateChange: ((State) -> Void)?
    var onMessage: ((OSCMessage) -> Void)?

    let host: String
    let port: UInt16
    let framing: OSCTCPFraming

    private let requiredInterface: NWInterface?
    private var connection: NWConnection?
    private var decoder: OSCStreamDecoder
    private let queue = DispatchQueue(label: "OSCTCPConnection")
    private var didReportEnd = false

    init(host: String, port: UInt16, framing: OSCTCPFraming, requiredInterface: NWInterface? = nil) {
        self.host = host
        self.port = port
        self.framing = framing
        self.requiredInterface = requiredInterface
        self.decoder = OSCStreamDecoder(framing: framing)
    }

    func start() {
        guard connection == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 5
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if let requiredInterface {
            parameters.requiredInterface = requiredInterface
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
        report(.connecting)
        connection.start(queue: queue)
        receive(on: connection)
    }

    func cancel() {
        didReportEnd = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    func send(_ message: OSCMessage) {
        guard let connection else { return }
        let framed = framing.frame(message.encoded())
        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    // Runs on `queue`.
    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            report(.ready)
        case .waiting(let error):
            // Connection refused, host unreachable and similar end up here.
            reportEnd(Self.failure(from: error))
        case .failed(let error):
            reportEnd(Self.failure(from: error))
        case .cancelled:
            break
        default:
            break
        }
    }

    // Runs on `queue`.
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let packets = self.decoder.push(data)
                var messages: [OSCMessage] = []
                for packet in packets {
                    if let decoded = try? OSCDecoder.decode(packet) {
                        messages.append(contentsOf: decoded)
                    }
                }
                if !messages.isEmpty {
                    let delivered = messages
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.didReportEnd else { return }
                        delivered.forEach { self.onMessage?($0) }
                    }
                }
            }
            if let error {
                self.reportEnd(Self.failure(from: error))
            } else if isComplete {
                self.reportEnd(.closed)
            } else {
                self.receive(on: connection)
            }
        }
    }

    private func report(_ state: State) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didReportEnd else { return }
            self.onStateChange?(state)
        }
    }

    private static func failure(from error: NWError) -> Failure {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED:
                return .refused
            case .ETIMEDOUT, .EHOSTUNREACH, .EHOSTDOWN, .ENETUNREACH:
                return .unreachable
            case .ECONNRESET, .EPIPE:
                return .closed
            default:
                // e.g. "Network is down", without the "NWError error 50" wrapping.
                return .other(String(cString: strerror(code.rawValue)))
            }
        case .dns:
            return .unreachable
        default:
            return .other(error.localizedDescription)
        }
    }

    private func reportEnd(_ failure: Failure) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didReportEnd else { return }
            self.didReportEnd = true
            self.connection?.cancel()
            self.onStateChange?(.failed(failure))
        }
    }
}
