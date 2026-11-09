import XCTest
@testable import CueSyncCore

final class EosChangeTests: XCTestCase {
    private func q(_ number: String, _ name: String) -> QLabCue {
        QLabCue(id: "q\(number)\(name)", number: number, name: name, listName: name, type: "Network")
    }

    private func e(_ number: String, _ label: String) -> EosCue {
        EosCue(list: 3, number: number, part: 0, index: 0, uid: "e\(number)", label: label, upTimeMs: 0)
    }

    func testPlansOneChangePerFixableRow() {
        let rows = CueComparison.compare(
            qlab: [q("1", "Same"), q("2", "New name"), q("3", " Added "), q("4A", "Bad"), q("5", "A"), q("5.0", "B")],
            eos: [e("1", "Same"), e("2", "Old name"), e("5", "x"), e("9", "Extra")]
        )
        let changes = EosChange.plan(from: rows, list: 3)
        XCTAssertEqual(changes, [
            EosChange(kind: .updateLabel, list: 3, number: "2", label: "New name", currentLabel: "Old name"),
            EosChange(kind: .add, list: 3, number: "3", label: "Added", currentLabel: nil),
            EosChange(kind: .delete, list: 3, number: "9", label: "", currentLabel: "Extra"),
        ])
        XCTAssertEqual(Set(changes.map(\.id)).count, changes.count)
    }

    func testAddCommandsCreateBlankCueWithTimeZeroAndLabel() {
        let change = EosChange(kind: .add, list: 3, number: "12.5", label: "Scene 2", currentLabel: nil)
        let commands = EosCommandBuilder.commands(for: change)
        XCTAssertEqual(commands.map(\.displayText), [
            "Record Only Cue 3/12.5#",
            "Cue 3/12.5 Time 0#",
            "Set label of cue 3/12.5 to “Scene 2”",
        ])
        XCTAssertEqual(commands[0].message(user: nil), OSCMessage("/eos/newcmd", [.string("Record Only Cue 3/12.5#")]))
        // Labels go to /eos/set as a string, never typed on the command line, whatever the user setting.
        XCTAssertEqual(commands[2].message(user: 61),
                       OSCMessage("/eos/set/cue/3/12.5/label", [.string("Scene 2")]))
    }

    func testCustomAddTemplate() {
        let change = EosChange(kind: .add, list: 1, number: "4", label: "X", currentLabel: nil)
        let commands = EosCommandBuilder.commands(for: change, addTemplate: "Blind Record Cue {list}/{cue}#")
        XCTAssertEqual(commands.first?.text, "Blind Record Cue 1/4#")
    }

    func testEditAndDeleteCommands() {
        let edit = EosChange(kind: .updateLabel, list: 2, number: "7", label: "Enter Time", currentLabel: "old")
        XCTAssertEqual(EosCommandBuilder.commands(for: edit),
                       [.setCueLabel(list: 2, number: "7", label: "Enter Time")])

        let clear = EosChange(kind: .updateLabel, list: 2, number: "7", label: "", currentLabel: "old")
        XCTAssertEqual(EosCommandBuilder.commands(for: clear).map { $0.message(user: nil) },
                       [OSCMessage("/eos/set/cue/2/7/label", [.string("")])])

        let delete = EosChange(kind: .delete, list: 2, number: "7", label: "", currentLabel: "old")
        XCTAssertEqual(EosCommandBuilder.commands(for: delete).map(\.text), ["Delete Cue 2/7 Enter Enter"])
        XCTAssertEqual(delete.summary, "Delete cue 2/7 “old”")
    }

    func testSendsAsOSCUserWhenSet() {
        XCTAssertEqual(EosCommand.line("Go#").message(user: 5).address, "/eos/user/5/newcmd")
        XCTAssertEqual(EosCommand.line("Go#").message(user: nil).address, "/eos/newcmd")
    }

    func testUserNumberParsing() {
        XCTAssertEqual(EosUserNumber.parse(""), .some(nil))
        XCTAssertEqual(EosUserNumber.parse("5"), .some(5))
        XCTAssertNil(EosUserNumber.parse("100"))
        XCTAssertNil(EosUserNumber.parse("x"))
    }
}
