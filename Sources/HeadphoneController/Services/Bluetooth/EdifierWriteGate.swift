import Foundation

/// Correlates the two supported RFCOMM completion callback variants with one outstanding write.
struct EdifierWriteGate {
    private var sequence: UInt = 0
    private(set) var pending: UInt?

    mutating func begin() -> UInt? {
        guard pending == nil else { return nil }
        repeat { sequence &+= 1 } while sequence == 0
        pending = sequence
        return sequence
    }

    mutating func finish(_ token: UInt) -> Bool {
        guard pending == token else { return false }
        pending = nil
        return true
    }

    mutating func cancel() { pending = nil }
}
