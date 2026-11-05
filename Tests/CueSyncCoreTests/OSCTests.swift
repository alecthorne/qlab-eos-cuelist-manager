import XCTest
@testable import CueSyncCore

final class OSCTests: XCTestCase {
    func testEncodesKnownBytes() {
        let data = OSCMessage("/a", [.int(1)]).encoded()
        XCTAssertEqual([UInt8](data), [
            0x2F, 0x61, 0x00, 0x00,       // "/a" + padding
            0x2C, 0x69, 0x00, 0x00,       // ",i" + padding
            0x00, 0x00, 0x00, 0x01,       // 1
        ])
    }

    func testEncodesMessageWithNoArguments() {
        let data = OSCMessage("/eos/ping").encoded()
        XCTAssertEqual(data.count, 12 + 4) // "/eos/ping\0" padded to 12, "," padded to 4
        XCTAssertEqual(try OSCDecoder.decode(data), [OSCMessage("/eos/ping")])
    }

    func testRoundTripsAllArgumentTypes() throws {
        let message = OSCMessage("/test/all", [
            .int(-42), .float(1.5), .string("héllo"), .blob(Data([1, 2, 3, 4, 5])),
            .bool(true), .bool(false), .null, .int64(1 << 40), .double(3.25), .string(""),
        ])
        XCTAssertEqual(try OSCDecoder.decode(message.encoded()), [message])
    }

    func testStringPaddingLengths() throws {
        for length in 0...8 {
            let text = String(repeating: "x", count: length)
            let message = OSCMessage("/s", [.string(text), .int(7)])
            let data = message.encoded()
            XCTAssertEqual(data.count % 4, 0)
            XCTAssertEqual(try OSCDecoder.decode(data), [message])
        }
    }

    func testDecodesBundle() throws {
        let first = OSCMessage("/one", [.int(1)]).encoded()
        let second = OSCMessage("/two", [.string("x")]).encoded()
        var bundle = Data()
        bundle.appendOSCString("#bundle")
        bundle.appendBigEndian(UInt64(1))
        bundle.appendBigEndian(UInt32(first.count))
        bundle.append(first)
        bundle.appendBigEndian(UInt32(second.count))
        bundle.append(second)
        XCTAssertEqual(try OSCDecoder.decode(bundle), [OSCMessage("/one", [.int(1)]), OSCMessage("/two", [.string("x")])])
    }

    func testTruncatedPacketThrows() {
        var data = OSCMessage("/a", [.int(1)]).encoded()
        data.removeLast(2)
        XCTAssertThrowsError(try OSCDecoder.decode(data))
    }

    func testMessageWithoutTypeTags() throws {
        var data = Data()
        data.appendOSCString("/old")
        XCTAssertEqual(try OSCDecoder.decode(data), [OSCMessage("/old")])
    }
}

final class FramingTests: XCTestCase {
    func testSLIPEscapesSpecialBytes() {
        let framed = OSCTCPFraming.slip.frame(Data([0x01, 0xC0, 0xDB, 0x02]))
        XCTAssertEqual([UInt8](framed), [0xC0, 0x01, 0xDB, 0xDC, 0xDB, 0xDD, 0x02, 0xC0])
    }

    func testSLIPReassemblesAcrossChunks() {
        let a = OSCMessage("/workspaces").encoded()
        let b = OSCMessage("/reply/x", [.string("{\"status\":\"ok\"}")]).encoded()
        var stream = OSCTCPFraming.slip.frame(a)
        stream.append(OSCTCPFraming.slip.frame(b))
        stream.append(OSCTCPFraming.slip.frame(Data([0xC0, 0xDB]))) // escaped content

        // Feed one byte at a time to exercise every split point, including mid-escape.
        var decoder = OSCStreamDecoder(framing: .slip)
        var packets: [Data] = []
        for byte in stream {
            packets.append(contentsOf: decoder.push(Data([byte])))
        }
        XCTAssertEqual(packets, [a, b, Data([0xC0, 0xDB])])
    }

    func testLengthPrefixReassemblesAcrossChunks() {
        let a = OSCMessage("/eos/ping").encoded()
        let b = OSCMessage("/eos/get/version").encoded()
        var stream = OSCTCPFraming.lengthPrefix.frame(a)
        stream.append(OSCTCPFraming.lengthPrefix.frame(b))

        var decoder = OSCStreamDecoder(framing: .lengthPrefix)
        let split = 6
        var packets = decoder.push(stream.prefix(split))
        XCTAssertTrue(packets.isEmpty)
        packets += decoder.push(stream.dropFirst(split))
        XCTAssertEqual(packets, [a, b])
    }
}

final class BoundedLogTests: XCTestCase {
    func testKeepsOnlyNewestLines() {
        var log = BoundedLog<Int>(capacity: 500)
        for i in 0..<520 { log.append(i) }
        XCTAssertEqual(log.lines.count, 500)
        XCTAssertEqual(log.lines.first, 20)
        XCTAssertEqual(log.lines.last, 519)
    }
}
