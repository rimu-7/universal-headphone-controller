import XCTest
@testable import HeadphoneController

final class EdifierWriteGateTests: XCTestCase {
    func testOnlyOneWriteCanBeOutstanding() {
        var gate = EdifierWriteGate()
        let token = gate.begin()!
        XCTAssertNil(gate.begin())
        XCTAssertTrue(gate.finish(token))
        XCTAssertNotNil(gate.begin())
    }

    func testDuplicateCompletionCannotFinishNextWrite() {
        var gate = EdifierWriteGate()
        let first = gate.begin()!
        XCTAssertTrue(gate.finish(first))
        let second = gate.begin()!
        XCTAssertFalse(gate.finish(first))
        XCTAssertEqual(gate.pending, second)
        XCTAssertTrue(gate.finish(second))
    }

    func testLateCompletionAfterReconnectCannotReleaseNewBuffer() {
        var gate = EdifierWriteGate()
        let old = gate.begin()!
        gate.cancel()
        XCTAssertFalse(gate.finish(old))
        let current = gate.begin()!
        XCTAssertFalse(gate.finish(old))
        XCTAssertEqual(gate.pending, current)
        XCTAssertTrue(gate.finish(current))
    }
}
