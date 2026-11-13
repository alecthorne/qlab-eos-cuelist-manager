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

    /// Logs a connection problem the app keeps retrying.
    func addRetrying(_ source: String, _ problem: String) {
        add(source, problem, then: "Retrying.")
    }

    /// Logs a problem followed by what the app did about it, e.g. "… Retrying."
    func add(_ source: String, _ problem: String, then outcome: String) {
        let sentence = problem.hasSuffix(".") || problem.hasSuffix("?") ? problem : problem + "."
        add(source, sentence + " " + outcome)
    }

    func clear() {
        log.removeAll()
    }
}
