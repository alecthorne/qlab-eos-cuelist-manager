import Foundation

/// A log that keeps only the newest `capacity` lines.
public struct BoundedLog<Element> {
    public let capacity: Int
    public private(set) var lines: [Element] = []

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public mutating func append(_ line: Element) {
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    /// Changes the newest line matching `predicate`, if it is still in the log.
    public mutating func updateLast(where predicate: (Element) -> Bool, _ change: (inout Element) -> Void) {
        guard let index = lines.lastIndex(where: predicate) else { return }
        change(&lines[index])
    }

    public mutating func removeAll() {
        lines.removeAll()
    }
}
