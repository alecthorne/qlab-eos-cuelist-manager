import XCTest
@testable import CueSyncCore

final class EosCueNumberTests: XCTestCase {
    func testCanonicalForms() {
        XCTAssertEqual(EosCueNumber.canonical("1"), "1")
        XCTAssertEqual(EosCueNumber.canonical(" 01 "), "1")
        XCTAssertEqual(EosCueNumber.canonical("1.50"), "1.5")
        XCTAssertEqual(EosCueNumber.canonical("1.0"), "1")
        XCTAssertEqual(EosCueNumber.canonical("0.5"), "0.5")
        XCTAssertEqual(EosCueNumber.canonical("9999.9999"), "9999.9999")
        XCTAssertEqual(EosCueNumber.canonical("12.0500"), "12.05")
    }

    func testRejectsNumbersEosCantUse() {
        for text in ["", "0", "0.0", "1A", "Pre", "1.2.3", ".5", "5.", "-1", "10000", "1.23456", "1,5", "１"] {
            XCTAssertNil(EosCueNumber.canonical(text), "\(text) should be rejected")
        }
    }

    func testNumericOrdering() {
        let sorted = ["10", "2", "1.5", "1.25", "1", "0.5"].sorted(by: EosCueNumber.isOrderedBefore)
        XCTAssertEqual(sorted, ["0.5", "1", "1.25", "1.5", "2", "10"])
    }
}

final class CueComparisonTests: XCTestCase {
    private func q(_ number: String, _ name: String, id: String? = nil) -> QLabCue {
        QLabCue(id: id ?? "q\(number)-\(name)", number: number, name: name, listName: name, type: "Network")
    }

    private func e(_ number: String, _ label: String, part: Int = 0, index: Int = 0) -> EosCue {
        EosCue(list: 1, number: number, part: part, index: index, uid: "e\(number)-\(part)", label: label, upTimeMs: 0)
    }

    func testClassifiesEveryCase() {
        let qlab = [
            q("1", "Preset"),          // matches
            q("2", "Scene 1"),         // label differs
            q("3", "Scene 2"),         // missing in Eos
            q("4", "A", id: "d1"),     // duplicate
            q("4.0", "B", id: "d2"),   // duplicate (same canonical number)
            q("5A", "Bad number"),     // invalid
        ]
        let eos = [
            e("1", "Preset"),
            e("2", "Old name"),
            e("2", "", part: 1),       // part: ignored
            e("4", "A"),
            e("7", "Extra"),           // not in QLab
        ]
        let rows = CueComparison.compare(qlab: qlab, eos: eos)

        XCTAssertEqual(rows.map(\.status), [
            .match, .labelDiffers, .missingInEos, .duplicateQLabNumber, .duplicateQLabNumber, .extraInEos, .invalidQLabNumber,
        ])
        XCTAssertEqual(rows.map(\.number), ["1", "2", "3", "4", "4", "7", nil])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "row ids must be unique")
        XCTAssertEqual(rows[1].eos?.label, "Old name")
        XCTAssertEqual(rows[3].eos?.number, "4")

        let counts = CueComparison.counts(rows)
        XCTAssertEqual(counts[.match], 1)
        XCTAssertEqual(counts[.duplicateQLabNumber], 2)
        XCTAssertEqual(rows.filter(\.isMismatch).count, 6)
    }

    func testMatchesNumbersWrittenDifferently() {
        let rows = CueComparison.compare(qlab: [q("1.50", "X")], eos: [e("1.5", "X")])
        XCTAssertEqual(rows.map(\.status), [.match])
    }

    func testLabelComparisonIgnoresSurroundingSpaces() {
        let rows = CueComparison.compare(qlab: [q("1", "Lights up ")], eos: [e("1", "Lights up")])
        XCTAssertEqual(rows.map(\.status), [.match])
    }

    func testEmptyInputs() {
        XCTAssertEqual(CueComparison.compare(qlab: [], eos: []), [])
        XCTAssertEqual(CueComparison.compare(qlab: [], eos: [e("1", "x")]).map(\.status), [.extraInEos])
    }
}
