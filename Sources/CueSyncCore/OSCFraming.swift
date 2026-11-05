import Foundation

/// How OSC packets are framed on a TCP stream.
public enum OSCTCPFraming: String, CaseIterable, Identifiable {
    /// OSC 1.1: packets wrapped in SLIP (RFC 1055), double-ended. Used by QLab
    /// on port 53000 and by Eos on TCP port 3037.
    case slip
    /// OSC 1.0: each packet prefixed with its length as a big-endian Int32.
    /// Used by Eos on TCP port 3032.
    case lengthPrefix

    public var id: String { rawValue }

    /// Wraps one OSC packet for sending.
    public func frame(_ packet: Data) -> Data {
        switch self {
        case .slip: return SLIP.encode(packet)
        case .lengthPrefix:
            var data = Data()
            data.appendBigEndian(UInt32(packet.count))
            data.append(packet)
            return data
        }
    }
}

/// Reassembles OSC packets from TCP stream chunks, which can split or join packets.
public struct OSCStreamDecoder {
    public let framing: OSCTCPFraming
    private var buffer: [UInt8] = []
    private var escaping = false

    public init(framing: OSCTCPFraming) {
        self.framing = framing
    }

    /// Feeds received bytes and returns every complete packet found so far.
    public mutating func push(_ data: Data) -> [Data] {
        switch framing {
        case .slip: return pushSLIP(data)
        case .lengthPrefix: return pushLengthPrefixed(data)
        }
    }

    private mutating func pushSLIP(_ data: Data) -> [Data] {
        var packets: [Data] = []
        for byte in data {
            if escaping {
                escaping = false
                switch byte {
                case SLIP.escEnd: buffer.append(SLIP.end)
                case SLIP.escEsc: buffer.append(SLIP.esc)
                default: buffer.append(byte) // protocol violation; keep the byte
                }
                continue
            }
            switch byte {
            case SLIP.end:
                if !buffer.isEmpty {
                    packets.append(Data(buffer))
                    buffer.removeAll(keepingCapacity: true)
                }
            case SLIP.esc:
                escaping = true
            default:
                buffer.append(byte)
            }
        }
        return packets
    }

    private mutating func pushLengthPrefixed(_ data: Data) -> [Data] {
        buffer.append(contentsOf: data)
        var packets: [Data] = []
        var offset = 0
        while buffer.count - offset >= 4 {
            let length = Int(buffer[offset]) << 24 | Int(buffer[offset + 1]) << 16
                | Int(buffer[offset + 2]) << 8 | Int(buffer[offset + 3])
            guard buffer.count - offset - 4 >= length else { break }
            packets.append(Data(buffer[(offset + 4)..<(offset + 4 + length)]))
            offset += 4 + length
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return packets
    }
}

enum SLIP {
    static let end: UInt8 = 0xC0
    static let esc: UInt8 = 0xDB
    static let escEnd: UInt8 = 0xDC
    static let escEsc: UInt8 = 0xDD

    static func encode(_ packet: Data) -> Data {
        var out: [UInt8] = [end]
        out.reserveCapacity(packet.count + 2)
        for byte in packet {
            switch byte {
            case end: out.append(contentsOf: [esc, escEnd])
            case esc: out.append(contentsOf: [esc, escEsc])
            default: out.append(byte)
            }
        }
        out.append(end)
        return Data(out)
    }
}
