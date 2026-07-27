import XCTest
@testable import XFakeCore

final class SharpnessReportTests: XCTestCase {
    /// A neutral panel for boundary tests: with a 1000px-wide panel, glyph
    /// pixels are simply 13000 / logical width, so boundaries are easy to hit
    /// exactly. Height is irrelevant to ratio/glyphPixels/verdict.
    let boundaryNative = ModeSpec(width: 1000, height: 1000, refresh: 60)

    private func verdict(logicalWidth: Int) -> String {
        SharpnessReport(panelNative: boundaryNative,
                        currentLogical: ModeSpec(width: logicalWidth, height: 1000, refresh: 60)).verdict
    }

    // MARK: - Verdict boundaries (keyed off glyph pixels, not ratio)

    func testExactNativeIsSharpestPossible() {
        let report = SharpnessReport(panelNative: boundaryNative, currentLogical: boundaryNative)
        XCTAssertEqual(report.ratio, 1.0)
        XCTAssertEqual(report.glyphPixels, 13.0)
        XCTAssertEqual(report.verdict, "1:1 or better — sharpest possible")
    }

    func testTwelvePointFivePixelsIsStillSharpest() {
        XCTAssertEqual(verdict(logicalWidth: 1040), "1:1 or better — sharpest possible") // 12.5px
    }

    func testJustBelowTwelvePointFiveIsCrisp() {
        XCTAssertEqual(verdict(logicalWidth: 1041), "crisp") // 12.49px
    }

    func testTenPixelsIsStillCrisp() {
        XCTAssertEqual(verdict(logicalWidth: 1300), "crisp") // exactly 10.0px
    }

    func testJustBelowTenPixelsIsSlightlySoft() {
        XCTAssertEqual(verdict(logicalWidth: 1301), "slightly soft") // 9.99px
    }

    func testNinePixelsIsStillSlightlySoft() {
        XCTAssertEqual(verdict(logicalWidth: 1444), "slightly soft") // 9.003px
    }

    func testBelowNinePixelsIsSoft() {
        XCTAssertEqual(verdict(logicalWidth: 1445), "soft — text may be hard to read") // 8.997px
    }

    // MARK: - Real hardware data points from live testing

    /// 3200x1350 on the 2560x1080 panel: the user reported this looks completely
    /// fine, which is what recalibrated these thresholds.
    func testLiveAcceptableCaseIsCrisp() {
        let report = SharpnessReport(panelNative: ModeSpec(width: 2560, height: 1080, refresh: 60),
                                     currentLogical: ModeSpec(width: 3200, height: 1350, refresh: 60))
        XCTAssertEqual(report.ratio, 1.25, accuracy: 0.0001)
        XCTAssertEqual(report.glyphPixels, 10.4, accuracy: 0.05)
        XCTAssertEqual(report.verdict, "crisp")
    }

    /// 3008x1692 on the 1920x1080 panel: the user reported this as blurry.
    func testLiveBlurryCaseIsSoft() {
        let report = SharpnessReport(panelNative: ModeSpec(width: 1920, height: 1080, refresh: 120),
                                     currentLogical: ModeSpec(width: 3008, height: 1692, refresh: 60))
        XCTAssertEqual(report.ratio, 1.5667, accuracy: 0.0001)
        XCTAssertEqual(report.glyphPixels, 8.3, accuracy: 0.05)
        XCTAssertEqual(report.verdict, "soft — text may be hard to read")
    }

    func testSummaryReportsBothPanelsRatioGlyphsAndTheOpticsCaveat() {
        let report = SharpnessReport(panelNative: ModeSpec(width: 2560, height: 1080, refresh: 60),
                                     currentLogical: ModeSpec(width: 3200, height: 1350, refresh: 60))
        XCTAssertEqual(report.summary,
            "panel native 2560×1080, showing 3200×1350 logical → 1.25× "
            + "(crisp; a 13pt glyph lands on 10.4 panel pixels). "
            + "Perceived sharpness also depends on the glasses' optics — trust your eyes over this label.")
    }
}
