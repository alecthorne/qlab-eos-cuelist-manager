import CueSyncCore
import XCTest

final class EosDefaultsTests: XCTestCase {
    func testDefaultUserIs61() {
        XCTAssertEqual(EosDefaults.user, 61)
        XCTAssertEqual(EosUserNumber.parse(String(EosDefaults.user)), .some(61))
    }

    func testEosNetworkAddress() {
        XCTAssertTrue(EosDefaults.isEosNetworkAddress("10.101.0.1"))
        XCTAssertTrue(EosDefaults.isEosNetworkAddress("10.101.100.101"))
        XCTAssertFalse(EosDefaults.isEosNetworkAddress("10.10.1.1"))
        XCTAssertFalse(EosDefaults.isEosNetworkAddress("10.1011.1.1"))
        XCTAssertFalse(EosDefaults.isEosNetworkAddress("110.101.1.1"))
        XCTAssertFalse(EosDefaults.isEosNetworkAddress("192.168.1.10"))
        XCTAssertFalse(EosDefaults.isEosNetworkAddress("10.101.1"))
        XCTAssertFalse(EosDefaults.isEosNetworkAddress("10.101.1.256"))
        XCTAssertFalse(EosDefaults.isEosNetworkAddress(""))
    }

    func testIPv4Address() {
        XCTAssertTrue(EosDefaults.isIPv4Address("10.101.100.101"))
        XCTAssertTrue(EosDefaults.isIPv4Address("127.0.0.1"))
        XCTAssertTrue(EosDefaults.isIPv4Address("0.0.0.0"))
        XCTAssertFalse(EosDefaults.isIPv4Address("10.101.100"))
        XCTAssertFalse(EosDefaults.isIPv4Address("10.101.100.256"))
        XCTAssertFalse(EosDefaults.isIPv4Address("10.101.100.101:3037"))
        XCTAssertFalse(EosDefaults.isIPv4Address("10.101..101"))
        XCTAssertFalse(EosDefaults.isIPv4Address("10.+1.1.1"))
        XCTAssertFalse(EosDefaults.isIPv4Address("10.101.100.1011"))
        XCTAssertFalse(EosDefaults.isIPv4Address("eos.local"))
        XCTAssertFalse(EosDefaults.isIPv4Address(""))
    }

    func testQLabPasscode() {
        XCTAssertTrue(QLabPasscode.isValid(""))
        XCTAssertTrue(QLabPasscode.isValid("0123"))
        XCTAssertFalse(QLabPasscode.isValid("123"))
        XCTAssertFalse(QLabPasscode.isValid("12345"))
        XCTAssertFalse(QLabPasscode.isValid("12a4"))
        XCTAssertFalse(QLabPasscode.isValid(" 1234"))
    }

    func testPicksFirstInterfaceOnEosNetwork() {
        let interfaces: [(name: String, addresses: [String])] = [
            ("en0", ["192.168.1.20"]),
            ("en7", ["169.254.3.4", "10.101.50.12"]),
            ("en8", ["10.101.60.1"]),
        ]
        XCTAssertEqual(EosDefaults.interface(in: interfaces), "en7")
    }

    func testNoInterfaceOnEosNetwork() {
        XCTAssertNil(EosDefaults.interface(in: [("en0", ["192.168.1.20"]), ("en1", ["10.100.1.1"])]))
        XCTAssertNil(EosDefaults.interface(in: []))
    }
}
