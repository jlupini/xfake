import XCTest
@testable import XFakeCore

final class TraceTests: XCTestCase {
    /// xfakeTraceEnabled is read once from the environment at process start,
    /// so it can't be flipped mid-test-run; test runs don't set XFAKE_TRACE,
    /// so it must reflect that.
    func testDisabledByDefaultInTestEnvironment() {
        XCTAssertFalse(xfakeTraceEnabled, "test process does not set XFAKE_TRACE=1")
    }

    /// The @autoclosure message must not be evaluated at all when tracing is
    /// disabled — callers rely on this to interpolate values for free.
    func testDisabledTraceNeverEvaluatesItsMessage() {
        var evaluated = false
        xfakeTrace({ evaluated = true; return "should not run" }())
        XCTAssertFalse(evaluated, "message closure must not be evaluated when XFAKE_TRACE is unset")
    }

    func testTraceLineFormatIncludesTimestampAndMessage() {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 26
        components.hour = 9; components.minute = 5; components.second = 3
        components.nanosecond = 250_000_000
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!

        let line = xfakeTraceLine("hello world", now: date)
        XCTAssertTrue(line.hasPrefix("[09:05:03.250] "), "unexpected line: \(line)")
        XCTAssertTrue(line.hasSuffix("hello world"))
    }
}
