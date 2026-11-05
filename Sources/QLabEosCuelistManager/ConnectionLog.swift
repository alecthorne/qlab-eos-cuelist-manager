import CueSyncCore
import Foundation

struct LogLine: Identifiable {
    let id = UUID()
    let date: Date
    let source: String
    let text: String
}

/// Connection events and errors, newest 500 kept. (The add/edit/delete action
/// log in step 3 is a separate log with the same 500-line limit.)
final class ConnectionLog: ObservableObject {
    @Published private(set) var log = BoundedLog<LogLine>(capacity: 500)

    func add(_ source: String, _ text: String) {
        log.append(LogLine(date: Date(), source: source, text: text))
    }

    func clear() {
        log.removeAll()
    }
}
