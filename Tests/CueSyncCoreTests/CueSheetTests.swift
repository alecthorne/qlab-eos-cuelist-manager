import CueSyncCore
import XCTest

final class CueSheetTests: XCTestCase {
    func testLine() {
        XCTAssertEqual(CueSheet.prefix(number: "3.5"), "• 3.5 - ")
        XCTAssertEqual(CueSheet.line(number: "3.5", name: "Ghost enters"), "• 3.5 - Ghost enters")
        XCTAssertEqual(CueSheet.line(number: "10", name: ""), "• 10 - ")
    }

    func testFileName() {
        XCTAssertEqual(CueSheet.fileName(workspace: "Hamlet", cueList: "Main Cue List"), "Hamlet - Main Cue List.pdf")
        XCTAssertEqual(CueSheet.fileName(workspace: "Act 1/2", cueList: "Video: Main"), "Act 1-2 - Video- Main.pdf")
        XCTAssertEqual(CueSheet.fileName(workspace: "Hamlet", cueList: "  "), "Hamlet.pdf")
        XCTAssertEqual(CueSheet.fileName(workspace: "", cueList: ""), "Cue List.pdf")
    }
}
