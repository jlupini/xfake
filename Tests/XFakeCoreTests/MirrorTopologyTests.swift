import XCTest
import CoreGraphics
@testable import XFakeCore

/// Covers which displays join the virtual display's mirror set, the menu
/// toggles that change that, and the repair path that restores it.
final class MirrorTopologyTests: XCTestCase {
    var system: MockDisplaySystem!
    var settings: SettingsStore!
    var controller: SessionController!

    let glasses = GlassesInfo(displayID: 5, vendorID: 13895, productID: 16640,
                              name: "XREAL One Pro",
                              native: ModeSpec(width: 3840, height: 1080, refresh: 60))

    /// A desk monitor: neither glasses nor built-in.
    let external = DisplayInfo(id: 9, name: "DELL U3223QE", vendorID: 4268, productID: 16498,
                               serialNumber: 1234, isBuiltin: false)

    override func setUp() {
        let defaults = UserDefaults(suiteName: "xfake-mirror-tests")!
        defaults.removePersistentDomain(forName: "xfake-mirror-tests")
        system = MockDisplaySystem()
        settings = SettingsStore(defaults: defaults)
        controller = SessionController(system: system, settings: settings)
    }

    override func tearDown() {
        UserDefaults(suiteName: "xfake-mirror-tests")?
            .removePersistentDomain(forName: "xfake-mirror-tests")
    }

    private func startSession() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
    }

    // MARK: - Default membership

    func testGlassesAndBuiltInMirrorTheVirtualDisplayWhichBecomesMain() {
        startSession()
        XCTAssertEqual(controller.state, .mirrored(virtual: 100, glasses: 5))
        XCTAssertEqual(system.topologies.last?.master, 100)
        XCTAssertEqual(system.topologies.last?.mirrors, [5, 1])
        XCTAssertEqual(system.mains.last, 100, "the virtual display becomes main")
        XCTAssertEqual(system.mirrorSource(of: 5), 100)
        XCTAssertEqual(system.mirrorSource(of: 1), 100)
    }

    func testOtherExternalDisplaysStayIndependentByDefault() {
        system.displays.append(external)
        startSession()
        XCTAssertEqual(system.topologies.last?.mirrors, [5, 1],
                       "a desk monitor is its own workspace unless asked otherwise")
        XCTAssertNil(system.mirrorSource(of: external.id))
    }

    func testTheVirtualDisplayIsNeverOfferedAsItsOwnMirror() {
        startSession()
        XCTAssertEqual(Set(controller.mirrorableDisplays.map(\.id)), [5, 1])
    }

    func testGlassesKeepTheirRealNameOnceMirroringHidesThemFromNSScreen() {
        system.displays[0] = DisplayInfo(id: 5, name: "Display 5", vendorID: 13895,
                                        productID: 16640, serialNumber: 0, isBuiltin: false)
        startSession()
        XCTAssertEqual(controller.mirrorableDisplays.first(where: { $0.id == 5 })?.name,
                       "XREAL One Pro")
    }

    // MARK: - Menu toggles

    func testTurningOffBuiltInReappliesTopologyWithoutIt() {
        startSession()
        let builtin = controller.mirrorableDisplays.first { $0.isBuiltin }!
        controller.setMirroring(false, for: builtin)
        XCTAssertEqual(system.topologies.last?.mirrors, [5])
        XCTAssertNil(system.mirrorSource(of: 1), "built-in released from the set")
        XCTAssertEqual(system.mirrorSource(of: 5), 100, "glasses stay mirrored")
    }

    func testTurningOnAnExternalDisplayAddsItToTheSet() {
        system.displays.append(external)
        startSession()
        controller.setMirroring(true, for: external)
        XCTAssertEqual(system.topologies.last?.mirrors, [5, 1, 9])
        XCTAssertEqual(system.mirrorSource(of: 9), 100)
    }

    func testAToggledPreferenceSurvivesAReconnect() {
        startSession()
        let builtin = controller.mirrorableDisplays.first { $0.isBuiltin }!
        controller.setMirroring(false, for: builtin)
        controller.handle(.glassesDisappeared(5))
        system.nextVirtualID = 200
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(200))
        XCTAssertEqual(system.topologies.last?.mirrors, [5],
                       "mirror preferences are keyed by display identity, not display ID")
    }

    func testTogglingWithNoLiveSessionTouchesNothing() {
        let builtin = DisplayInfo(id: 1, name: "Built-in Display", vendorID: 1552,
                                  productID: 41039, serialNumber: 4251086178, isBuiltin: true)
        controller.setMirroring(false, for: builtin)
        XCTAssertTrue(system.topologies.isEmpty)
        XCTAssertFalse(controller.isMirroring(builtin), "the preference is still recorded")
    }

    // MARK: - Auto-mirror master switch

    func testAutoMirrorOffLeavesTheTopologyAloneOnConnect() {
        settings.autoMirror = false
        startSession()
        XCTAssertEqual(controller.state, .mirrored(virtual: 100, glasses: 5))
        XCTAssertTrue(system.topologies.isEmpty, "no mirroring, and the main display is untouched")
        XCTAssertTrue(system.mains.isEmpty)
    }

    func testAutoMirrorOffStillHonoursAnExplicitToggle() {
        settings.autoMirror = false
        startSession()
        let builtin = DisplayInfo(id: 1, name: "Built-in Display", vendorID: 1552,
                                  productID: 41039, serialNumber: 4251086178, isBuiltin: true)
        controller.setMirroring(true, for: builtin)
        XCTAssertEqual(system.topologies.last?.mirrors, [5, 1],
                       "an explicit toggle is an instruction regardless of the master switch")
    }

    func testEnablingAutoMirrorAppliesTheTopologyImmediately() {
        settings.autoMirror = false
        startSession()
        XCTAssertTrue(system.topologies.isEmpty)
        controller.setAutoMirror(true)
        XCTAssertEqual(system.topologies.last?.mirrors, [5, 1])
        XCTAssertTrue(controller.isAutoMirrorEnabled)
    }

    func testAutoMirrorOffSuppressesRepair() {
        startSession()
        settings.autoMirror = false
        system.mirrorSources.removeAll()
        controller.handle(.reconfigured)
        XCTAssertEqual(system.topologies.count, 1, "repair must not fight a user who turned it off")
    }

    // MARK: - Repair

    /// The live-reported failure: after a reconfiguration the built-in dropped
    /// out of the mirror set and stayed out.
    func testRepairRestoresADisplayThatFellOutOfTheSet() {
        startSession()
        system.mirrorSources[1] = nil // built-in silently left the set
        controller.handle(.reconfigured)
        XCTAssertEqual(system.topologies.count, 2)
        XCTAssertEqual(system.topologies.last?.mirrors, [5, 1])
    }

    func testRepairDoesNothingWhenTheSetAlreadyMatches() {
        startSession()
        controller.handle(.reconfigured)
        XCTAssertEqual(system.topologies.count, 1, "no churn when reality already matches intent")
    }

    func testRepairDropsADisplayThatWentAwayInsteadOfWedging() {
        startSession()
        system.displays.removeAll { $0.isBuiltin } // built-in unplugged/asleep
        system.mirrorSources.removeAll()           // and the whole set collapsed
        controller.handle(.reconfigured)
        XCTAssertEqual(system.topologies.last?.mirrors, [5],
                       "a vanished display leaves the desired set rather than blocking repair")
    }

    func testRepairIsAlreadySatisfiedWhenOnlyTheVanishedDisplayIsMissing() {
        startSession()
        system.displays.removeAll { $0.isBuiltin }
        system.mirrorSources[1] = nil
        controller.handle(.reconfigured)
        XCTAssertEqual(system.topologies.count, 1,
                       "an unplugged display is simply out of scope — nothing to repair")
    }
}
