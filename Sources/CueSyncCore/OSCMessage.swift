import Foundation

/// A single OSC argument.
public enum OSCArgument: Equatable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)
    case bool(Bool)
    case null
    case int64(Int64)
    case double(Double)

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return Int(value)
        case .int64(let value): return Int(value)
        case .float(let value): return Int(value)
        case .double(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .int64(let value): return Double(value)
        case .float(let value): return Double(value)
        case .double(let value): return value
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return Double(value)
        default: return nil
        }
    }
}

/// An OSC message: an address pattern plus arguments.
public struct OSCMessage: Equatable, CustomStringConvertible {
    public var address: String
    public var arguments: [OSCArgument]

    public init(_ address: String, _ arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }

    /// The address split on "/", without the empty leading component.
    public var addressComponents: [String] {
        address.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public var description: String {
        guard !arguments.isEmpty else { return address }
        let args = arguments.map { argument -> String in
            switch argument {
            case .int(let v): return String(v)
            case .int64(let v): return String(v)
            case .float(let v): return String(v)
            case .double(let v): return String(v)
            case .string(let v): return "\"\(v)\""
            case .bool(let v): return v ? "true" : "false"
            case .blob(let v): return "<\(v.count) bytes>"
            case .null: return "nil"
            }
        }
        return address + " " + args.joined(separator: ", ")
    }

    /// Encodes the message as an OSC 1.0 packet.
    public func encoded() -> Data {
        var data = Data()
        data.appendOSCString(address)
        var typeTags = ","
        var payload = Data()
        for argument in arguments {
            switch argument {
            case .int(let v):
                typeTags.append("i")
                payload.appendBigEndian(UInt32(bitPattern: v))
            case .float(let v):
                typeTags.append("f")
                payload.appendBigEndian(v.bitPattern)
            case .string(let v):
                typeTags.append("s")
                payload.appendOSCString(v)
            case .blob(let v):
                typeTags.append("b")
                payload.appendBigEndian(UInt32(v.count))
                payload.append(v)
                payload.appendPadding(forLength: v.count)
            case .bool(let v):
                typeTags.append(v ? "T" : "F")
            case .null:
                typeTags.append("N")
            case .int64(let v):
                typeTags.append("h")
                payload.appendBigEndian(UInt64(bitPattern: v))
            case .double(let v):
                typeTags.append("d")
                payload.appendBigEndian(v.bitPattern)
            }
        }
        data.appendOSCString(typeTags)
        data.append(payload)
        return data
    }
}

public enum OSCDecodeError: Error, Equatable {
    case truncated
    case badString
    case unsupportedType(Character)
}

/// Decodes OSC packets. Bundles are flattened into their messages.
public enum OSCDecoder {
    public static func decode(_ data: Data) throws -> [OSCMessage] {
        var reader = OSCReader(bytes: [UInt8](data))
        return try decodePacket(&reader)
    }

    private static func decodePacket(_ reader: inout OSCReader) throws -> [OSCMessage] {
        if reader.bytes.starts(with: Array("#bundle".utf8) + [0]) {
            _ = try reader.readString()        // "#bundle"
            _ = try reader.readUInt64()        // time tag (ignored)
            var messages: [OSCMessage] = []
            while reader.position < reader.bytes.count {
                let size = Int(try reader.readUInt32())
                let element = try reader.readBytes(size)
                var sub = OSCReader(bytes: element)
                messages.append(contentsOf: try decodePacket(&sub))
            }
            return messages
        }
        return [try decodeMessage(&reader)]
    }

    private static func decodeMessage(_ reader: inout OSCReader) throws -> OSCMessage {
        let address = try reader.readString()
        // Old OSC senders may omit the type tag string entirely.
        guard reader.position < reader.bytes.count else { return OSCMessage(address) }
        let tags = try reader.readString()
        guard tags.hasPrefix(",") else { return OSCMessage(address) }

        var arguments: [OSCArgument] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i": arguments.append(.int(Int32(bitPattern: try reader.readUInt32())))
            case "f": arguments.append(.float(Float(bitPattern: try reader.readUInt32())))
            case "s", "S": arguments.append(.string(try reader.readString()))
            case "b":
                let size = Int(try reader.readUInt32())
                let bytes = try reader.readBytes(size)
                try reader.skipPadding(forLength: size)
                arguments.append(.blob(Data(bytes)))
            case "T": arguments.append(.bool(true))
            case "F": arguments.append(.bool(false))
            case "N", "I": arguments.append(.null)
            case "h", "t": arguments.append(.int64(Int64(bitPattern: try reader.readUInt64())))
            case "d": arguments.append(.double(Double(bitPattern: try reader.readUInt64())))
            case "c", "r", "m": arguments.append(.int(Int32(bitPattern: try reader.readUInt32())))
            default: throw OSCDecodeError.unsupportedType(tag)
            }
        }
        return OSCMessage(address, arguments)
    }
}

struct OSCReader {
    let bytes: [UInt8]
    var position = 0

    mutating func readString() throws -> String {
        guard position < bytes.count,
              let end = bytes[position...].firstIndex(of: 0) else { throw OSCDecodeError.badString }
        let string = String(decoding: bytes[position..<end], as: UTF8.self)
        let next = (end + 4) & ~3
        guard next <= bytes.count else { throw OSCDecodeError.truncated }
        position = next
        return string
    }

    mutating func readUInt32() throws -> UInt32 {
        let slice = try readBytes(4)
        return slice.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let slice = try readBytes(8)
        return slice.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, position + count <= bytes.count else { throw OSCDecodeError.truncated }
        let slice = Array(bytes[position..<(position + count)])
        position += count
        return slice
    }

    mutating func skipPadding(forLength length: Int) throws {
        let pad = (4 - length % 4) % 4
        guard position + pad <= bytes.count else { throw OSCDecodeError.truncated }
        position += pad
    }
}

extension Data {
    mutating func appendOSCString(_ string: String) {
        var bytes = Array(string.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        append(contentsOf: bytes)
    }

    mutating func appendPadding(forLength length: Int) {
        let pad = (4 - length % 4) % 4
        if pad > 0 { append(contentsOf: [UInt8](repeating: 0, count: pad)) }
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ])
    }

    mutating func appendBigEndian(_ value: UInt64) {
        appendBigEndian(UInt32(truncatingIfNeeded: value >> 32))
        appendBigEndian(UInt32(truncatingIfNeeded: value))
    }
}
