import XCTest
@testable import XFakeCore

final class ModeLabelTests: XCTestCase {
    let native = ModeSpec(width: 2560, height: 1080, refresh: 60)

    // MARK: - Labels state the tradeoff, not a verdict

    func testNativeIsLabeledSharpest() {
        XCTAssertEqual(modeLabel(for: native, native: native), "2560 × 1080 · native · sharpest")
    }

    func testTenPercentOverReportsSpaceAndGlyphPixels() {
        let mode = ModeSpec(width: 2816, height: 1188, refresh: 60)
        XCTAssertEqual(modeLabel(for: mode, native: native), "2816 × 1188 · +10% space · 11.8px text")
    }

    /// The live-tested case: the user found this completely acceptable, so it
    /// must carry no soft warning.
    func testTwentyFivePercentOverCarriesNoWarning() {
        let mode = ModeSpec(width: 3200, height: 1350, refresh: 60)
        XCTAssertEqual(modeLabel(for: mode, native: native), "3200 × 1350 · +25% space · 10.4px text")
    }

    func testDoubleNativeWarnsItMayLookSoft() {
        let mode = ModeSpec(width: 5120, height: 2160, refresh: 60)
        XCTAssertEqual(modeLabel(for: mode, native: native),
                       "5120 × 2160 · +100% space · 6.5px text · may look soft")
    }

    func testWarningAppearsOnlyBelowNinePixels() {
        // 1.44x -> 9.03px: no warning. 1.45x -> 8.97px: warning.
        let justAbove = ModeSpec(width: 3686, height: 1555, refresh: 60)
        let justBelow = ModeSpec(width: 3712, height: 1566, refresh: 60)
        XCTAssertFalse(modeLabel(for: justAbove, native: native).contains("may look soft"))
        XCTAssertTrue(modeLabel(for: justBelow, native: native).contains("may look soft"))
    }

    // MARK: - Menu presets

    func testPresetsAreNativeFirstAndDeduplicated() {
        let ladder = ModeLadder.generate(native: native)
        let presets = modePresets(ladder: ladder, native: native)
        XCTAssertEqual(presets.first, native)
        XCTAssertEqual(presets.count, Set(presets).count, "presets must not repeat a mode")
        XCTAssertTrue(presets.allSatisfy { ladder.contains($0) }, "presets must be real ladder entries")
    }

    func testWidescreenPresetsSnapToNearestLadderEntry() {
        let ladder = ModeLadder.generate(native: native)
        XCTAssertEqual(modePresets(ladder: ladder, native: native), [
            ModeSpec(width: 2560, height: 1080, refresh: 60),  // 1.00x
            ModeSpec(width: 2816, height: 1188, refresh: 60),  // 1.10x
            ModeSpec(width: 3200, height: 1350, refresh: 60),  // 1.25x
            ModeSpec(width: 3840, height: 1620, refresh: 60),  // 1.50x
            ModeSpec(width: 4352, height: 1836, refresh: 60),  // 1.75x
            ModeSpec(width: 5120, height: 2160, refresh: 60),  // 2.00x
        ])
    }

    func testSixteenNinePresetsSnapToNearestLadderEntry() {
        let sixteenNine = ModeSpec(width: 1920, height: 1080, refresh: 120)
        let ladder = ModeLadder.generate(native: sixteenNine)
        XCTAssertEqual(modePresets(ladder: ladder, native: sixteenNine), [
            ModeSpec(width: 1920, height: 1080, refresh: 120),
            ModeSpec(width: 2112, height: 1188, refresh: 120),
            ModeSpec(width: 2400, height: 1350, refresh: 120),
            ModeSpec(width: 2816, height: 1584, refresh: 120),
            ModeSpec(width: 3328, height: 1872, refresh: 120),
            ModeSpec(width: 3840, height: 2160, refresh: 120),
        ])
    }

    func testEmptyLadderYieldsNoPresets() {
        XCTAssertTrue(modePresets(ladder: [], native: native).isEmpty)
    }
}
