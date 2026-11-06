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
