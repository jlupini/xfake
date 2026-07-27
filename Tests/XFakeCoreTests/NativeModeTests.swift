import XCTest
@testable import XFakeCore

final class NativeModeTests: XCTestCase {
    func testPicksHighestOneXModeAtHighestRefresh() {
        let raw = [
            RawMode(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refresh: 60),  // HiDPI, not 1x
            RawMode(width: 3840, height: 1080, pixelWidth: 3840, pixelHeight: 1080, refresh: 60),  // native
            RawMode(width: 1920, height: 540,  pixelWidth: 1920, pixelHeight: 540,  refresh: 60),  // small 1x
        ]
        XCTAssertEqual(NativeMode.select(from: raw), ModeSpec(width: 3840, height: 1080, refresh: 60))
    }

    func testPrefersHigherRefreshAtSamePixels() {
        let raw = [
            RawMode(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refresh: 60),
            RawMode(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refresh: 120),
        ]
        XCTAssertEqual(NativeMode.select(from: raw)?.refresh, 120)
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(NativeMode.select(from: []))
    }
}
