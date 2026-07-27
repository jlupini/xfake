import XCTest
@testable import XFakeCore

final class SettingsStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var store: SettingsStore!

    override func setUp() {
        defaults = UserDefaults(suiteName: "xfake-tests")!
        defaults.removePersistentDomain(forName: "xfake-tests")
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "xfake-tests")
    }

    func testEnabledDefaultsToTrue() {
        XCTAssertTrue(store.isEnabled)
        store.isEnabled = false
        XCTAssertFalse(store.isEnabled)
    }

    func testPreferredModeIsPerAspect() {
        let ultrawide = AspectRatio(of: ModeSpec(width: 3840, height: 1080, refresh: 60))
        let sixteenNine = AspectRatio(of: ModeSpec(width: 1920, height: 1080, refresh: 120))
        XCTAssertNil(store.preferredMode(for: ultrawide))

        store.setPreferredMode(ModeSpec(width: 4160, height: 1170, refresh: 60), for: ultrawide)
        store.setPreferredMode(ModeSpec(width: 2240, height: 1260, refresh: 120), for: sixteenNine)

        XCTAssertEqual(store.preferredMode(for: ultrawide), ModeSpec(width: 4160, height: 1170, refresh: 60))
        XCTAssertEqual(store.preferredMode(for: sixteenNine), ModeSpec(width: 2240, height: 1260, refresh: 120))
    }

    func testOverwritingPreferredModeReturnsNewValue() {
        let ultrawide = AspectRatio(of: ModeSpec(width: 3840, height: 1080, refresh: 60))
        store.setPreferredMode(ModeSpec(width: 4160, height: 1170, refresh: 60), for: ultrawide)
        store.setPreferredMode(ModeSpec(width: 4480, height: 1260, refresh: 60), for: ultrawide)
        XCTAssertEqual(store.preferredMode(for: ultrawide), ModeSpec(width: 4480, height: 1260, refresh: 60))
    }

    func testGarbageDataUnderPreferredKeyDecodesToNil() {
        let ultrawide = AspectRatio(of: ModeSpec(width: 3840, height: 1080, refresh: 60))
        defaults.set(Data("not json".utf8), forKey: "preferred.\(ultrawide.w)x\(ultrawide.h)")
        XCTAssertNil(store.preferredMode(for: ultrawide))
    }
}
