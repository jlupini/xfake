import Foundation

/// Opt-in diagnostic tracing, enabled by setting `XFAKE_TRACE=1` in the
/// environment before launching xfake. Read once at process start.
public let xfakeTraceEnabled = ProcessInfo.processInfo.environment["XFAKE_TRACE"] == "1"

/// Builds the "[HH:mm:ss.SSS] message" line written by `xfakeTrace`. Split out
/// so the formatting can be unit-tested independently of the process-wide
/// `xfakeTraceEnabled` flag (which is fixed for the life of the process).
func xfakeTraceLine(_ message: String, now: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return "[\(formatter.string(from: now))] \(message)"
}

/// Prints `message` to stderr with a millisecond-resolution timestamp prefix
/// when `XFAKE_TRACE=1` is set; a no-op otherwise. The `@autoclosure` means
/// `message` is never even evaluated when tracing is disabled, so call sites
/// can freely interpolate values without a runtime cost in normal use.
public func xfakeTrace(_ message: @autoclosure () -> String) {
    guard xfakeTraceEnabled else { return }
    FileHandle.standardError.write((xfakeTraceLine(message()) + "\n").data(using: .utf8)!)
}
