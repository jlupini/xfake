import XCTest
@testable import XFakeCore

final class ModeLadderTests: XCTestCase {
    let ultrawide = ModeSpec(width: 3840, height: 1080, refresh: 60)     // 32:9
    let widescreen = ModeSpec(width: 2560, height: 1080, refresh: 60)    // 64:27
    let sixteenNine = ModeSpec(width: 1920, height: 1080, refresh: 120)  // 16:9

    // MARK: - Range and endpoints

    func testLadderStartsAtNativeAndEndsAtExactlyDoubleNative() {
        for native in [ultrawide, widescreen, sixteenNine] {
            let ladder = ModeLadder.generate(native: native)
            XCTAssertEqual(ladder.first, native, "\(native) should start at native")
            XCTAssertEqual(ladder.last,
                           ModeSpec(width: native.width * 2, height: native.height * 2,
                                    refresh: native.refresh),
                           "\(native) should end at exactly 2x native")
        }
    }

    func testAllModesHoldTheExactAspect() {
        for native in [ultrawide, widescreen, sixteenNine] {
            for mode in ModeLadder.generate(native: native) {
                XCTAssertEqual(mode.width * native.height, mode.height * native.width,
                               "\(mode) breaks the aspect of \(native)")
            }
        }
    }

    func testRefreshRateIsInheritedFromNative() {
        XCTAssertTrue(ModeLadder.generate(native: sixteenNine).allSatisfy { $0.refresh == 120 })
        XCTAssertTrue(ModeLadder.generate(native: ultrawide).allSatisfy { $0.refresh == 60 })
    }

    func testLadderIsAscendingWithNoDuplicateAtTheTierBoundary() {
        for native in [ultrawide, widescreen, sixteenNine] {
            let widths = ModeLadder.generate(native: native).map(\.width)
            XCTAssertEqual(widths, widths.sorted(), "\(native) ladder not ascending")
            XCTAssertEqual(widths.count, Set(widths).count, "\(native) ladder has duplicates")
        }
    }

    // MARK: - Two-tier stepping

    func testUltrawideUsesFineStepsToOneAndAQuarterThenCoarse() {
        let ladder = ModeLadder.generate(native: ultrawide)
        XCTAssertEqual(ladder.count, 28)
        XCTAssertEqual(ladder[1], ModeSpec(width: 3904, height: 1098, refresh: 60)) // fine 64x18
        let fine = ladder.filter { $0.width <= 4800 }   // 1.25x boundary
        XCTAssertEqual(fine.count, 16)
        XCTAssertEqual(fine.last, ModeSpec(width: 4800, height: 1350, refresh: 60))
        XCTAssertEqual(ladder[16], ModeSpec(width: 4864, height: 1368, refresh: 60)) // coarse 256x72
    }

    func testUltrawideLadderKeepsTheBetterDisplaySweetSpot() {
        XCTAssertTrue(ModeLadder.generate(native: ultrawide)
            .contains(ModeSpec(width: 4160, height: 1170, refresh: 60)))
    }

    func testWidescreenNeedsNoStepDoubling() {
        let ladder = ModeLadder.generate(native: widescreen)
        XCTAssertEqual(ladder.count, 19)
        XCTAssertEqual(ladder[1], ModeSpec(width: 2624, height: 1107, refresh: 60)) // aspect unit 64x27
        XCTAssertEqual(ladder.last, ModeSpec(width: 5120, height: 2160, refresh: 60))
    }

    func testSixteenNineStepsThirtyTwoByEighteen() {
        let ladder = ModeLadder.generate(native: sixteenNine)
        XCTAssertEqual(ladder.count, 28)
        XCTAssertEqual(ladder[1], ModeSpec(width: 1952, height: 1098, refresh: 120))
        XCTAssertEqual(ladder.last, ModeSpec(width: 3840, height: 2160, refresh: 120))
    }
}
