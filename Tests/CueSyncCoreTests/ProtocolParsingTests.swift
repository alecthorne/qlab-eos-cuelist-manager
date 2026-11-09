import XCTest
@testable import CueSyncCore

final class QLabParsingTests: XCTestCase {
    private func reply(_ address: String, _ json: String) -> OSCMessage {
        OSCMessage("/reply" + address, [.string(json)])
    }

    func testParsesWorkspaces() throws {
        let message = reply("/workspaces", """
        {"address":"/workspaces","status":"ok","data":[
          {"uniqueID":"W1","displayName":"Show.qlab5","port":53000,"version":"5.4"}
        ]}
        """)
        let parsed = try XCTUnwrap(QLabReply.parse(message))
        XCTAssertTrue(parsed.isOK)
        XCTAssertEqual(parsed.address, "/workspaces")
        XCTAssertEqual(QLabWorkspace.parseList(parsed.data), [QLabWorkspace(id: "W1", displayName: "Show.qlab5")])
    }

    func testFlattensNumberedCuesInOrder() throws {
        let message = reply("/workspace/W1/cueLists", """
        {"workspace_id":"W1","address":"/workspace/W1/cueLists","status":"ok","data":[
          {"uniqueID":"L1","number":"","name":"Main","listName":"Main","type":"Cue List","cues":[
            {"uniqueID":"c1","number":"1","name":"Preset","listName":"Preset","type":"Memo"},
            {"uniqueID":"c2","number":"","name":"","listName":"Wait","type":"Wait"},
            {"uniqueID":"g1","number":"2","name":"Scene 1","listName":"Scene 1","type":"Group","cues":[
              {"uniqueID":"c3","number":"2.5","name":"Lights up","listName":"Lights up","type":"Network"},
              {"uniqueID":"c4","number":"","name":"","listName":"Audio","type":"Audio"}
            ]},
            {"uniqueID":"c5","number":"3","name":"","listName":"Network: Go 3","type":"Network"}
          ]},
          {"uniqueID":"L2","number":"","name":"Sound FX","listName":"Sound FX","type":"Cart","cues":[]}
        ]}
        """)
        let parsed = try XCTUnwrap(QLabReply.parse(message))
        XCTAssertEqual(parsed.workspaceID, "W1")
        let lists = QLabCue.parseList(parsed.data)
        XCTAssertEqual(lists.map(\.id), ["L1", "L2"])

        let numbered = lists[0].numberedDescendants()
        XCTAssertEqual(numbered.map(\.number), ["1", "2", "2.5", "3"])
        XCTAssertEqual(numbered.last?.displayName, "Network: Go 3")
    }

    func testIgnoresNonReplies() {
        XCTAssertNil(QLabReply.parse(OSCMessage("/update/workspace/W1")))
        XCTAssertNil(QLabReply.parse(OSCMessage("/reply/x", [.string("not json")])))
    }
}

final class EosParsingTests: XCTestCase {
    func testRequests() {
        XCTAssertEqual(EosRequest.cueCount(list: 5).address, "/eos/get/cue/5/count")
        XCTAssertEqual(EosRequest.cue(list: 5, index: 3).address, "/eos/get/cue/5/index/3")
        XCTAssertEqual(EosRequest.subscribe, OSCMessage("/eos/subscribe", [.int(1)]))
    }

    func testParsesCueCount() {
        let output = EosOutput.parse(OSCMessage("/eos/out/get/cue/5/count", [.int(12)]))
        XCTAssertEqual(output, .cueCount(list: 5, count: 12))
    }

    func testParsesCue() {
        let message = OSCMessage("/eos/out/get/cue/5/2.5/0/list/3/12", [
            .int(3), .string("UID-123"), .string("Lights up"), .int(3000), .int(0),
        ])
        let expected = EosCue(list: 5, number: "2.5", part: 0, index: 3, uid: "UID-123", label: "Lights up", upTimeMs: 3000)
        XCTAssertEqual(EosOutput.parse(message), .cue(expected, listCount: 12))
    }

    func testIgnoresCueSubReplies() {
        let fx = OSCMessage("/eos/out/get/cue/5/2.5/0/fx/list/0/1", [.int(0), .string("UID")])
        XCTAssertEqual(EosOutput.parse(fx), .other)
    }

    func testParsesNotifyAndActive() {
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/notify/cue/5/list/0/1", [.int(9), .string("2")])),
                       .cueListChanged(list: 5))
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/active/cue/5/2.5", [.float(0.5)])),
                       .activeCue(list: 5, number: "2.5", progress: 0.5))
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/active/cue/text", [.string("5/2.5 Lights up 3.0 50%")])),
                       .activeCueText("5/2.5 Lights up 3.0 50%"))
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/pending/cue/5/3", [])),
                       .pendingCue(list: 5, number: "3"))
    }

    func testParsesVersionShowAndPing() {
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/get/version", [.string("3.2.10")])), .version("3.2.10"))
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/show/name", [.string("Hamlet")])), .showName("Hamlet"))
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/show/loaded")), .showReset)
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/ping")), .ping)
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/cmd", [.string("LIVE: Cue 1/5 Time 0 #")])),
                       .commandLine(user: nil, text: "LIVE: Cue 1/5 Time 0 #"))
        XCTAssertEqual(EosOutput.parse(OSCMessage("/eos/out/user/61/cmd", [.string("LIVE: Error: x")])),
                       .commandLine(user: 61, text: "LIVE: Error: x"))
        XCTAssertEqual(EosOutput.parse(OSCMessage("/qlab/whatever")), .other)
    }

    func testCueListNumberHasNoDefault() {
        XCTAssertNil(EosCueListNumber.parse(""))
        XCTAssertNil(EosCueListNumber.parse("0"))
        XCTAssertNil(EosCueListNumber.parse("1.5"))
        XCTAssertNil(EosCueListNumber.parse("abc"))
        XCTAssertEqual(EosCueListNumber.parse(" 7 "), 7)
    }
}
