// Minimal assertion adapter for Command Line Tools installations without XCTest/SwiftPM.
// Scripts/test_protocols.sh runs the same test methods used by the XCTest target.
import Foundation

class XCTestCase {}
var assertionFailures = 0

func record(_ passed: Bool, _ message: String, file: StaticString, line: UInt) {
    if !passed { assertionFailures += 1; print("FAIL \(file):\(line) \(message)") }
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    let a = lhs(), b = rhs()
    record(a == b, "\(a) != \(b) \(message)", file: file, line: line)
}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(value(), message, file: file, line: line)
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(!value(), message, file: file, line: line)
}
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(value() == nil, message, file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(value() != nil, message, file: file, line: line)
}
func XCTAssertLessThanOrEqual<T: Comparable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(lhs() <= rhs(), message, file: file, line: line)
}
func XCTAssertGreaterThan<T: Comparable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(lhs() > rhs(), message, file: file, line: line)
}
