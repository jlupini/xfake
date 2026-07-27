import XCTest
import CoreGraphics
@testable import XFakeCore

final class MockHandle: VirtualHandle {
    let displayID: CGDirectDisplayID
    init(_ id: CGDirectDisplayID) { displayID = id }
}

final class MockDisplaySystem: DisplaySystem {
    var createdConfigs: [VirtualDisplayConfig] = []
    var terminations: [(CGDirectDisplayID) -> Void] = []
    var failCreates = 0
    var nextVirtualID: CGDirectDisplayID = 100
    var mirrors: [(master: CGDirectDisplayID, mirror: CGDirectDisplayID)] = []
    var unmirrors: [CGDirectDisplayID] = []
    var mains: [CGDirectDisplayID] = []
    var appliedModes: [(CGDirectDisplayID, ModeSpec)] = []
    var mirroredIDs: Set<CGDirectDisplayID> = []
    var builtin: CGDirectDisplayID? = 1
    var mirrorResult = true
    var isOnlineResult = true
    var onUnmirror: (() -> Void)?
    var currentModeResult: ModeSpec?
    var resetTopologyCalls: [CGDirectDisplayID] = []
    var resetTopologyResult = true

    func createVirtualDisplay(_ config: VirtualDisplayConfig, onTermination: @escaping (CGDirectDisplayID) -> Void) -> VirtualHandle? {
        createdConfigs.append(config)
        terminations.append(onTermination)
        if failCreates > 0 { failCreates -= 1; return nil }
        let id = nextVirtualID
        nextVirtualID += 1
        return MockHandle(id)
    }
    func mirrorAndSetMain(master: CGDirectDisplayID, mirror: CGDirectDisplayID) -> Bool {
        guard mirrorResult else { return false }
        mirrors.append((master, mirror)); mirroredIDs.insert(mirror); mains.append(master)
        return true
    }
    func unmirror(_ display: CGDirectDisplayID) -> Bool {
        unmirrors.append(display); mirroredIDs.remove(display)
        onUnmirror?()
        return true
    }
    func setMain(_ display: CGDirectDisplayID) -> Bool { mains.append(display); return true }
    func applyMode(_ display: CGDirectDisplayID, mode: ModeSpec) -> Bool {
        appliedModes.append((display, mode)); return true
    }
    func currentMode(of display: CGDirectDisplayID) -> ModeSpec? { currentModeResult }
    func isMirrored(_ display: CGDirectDisplayID) -> Bool { mirroredIDs.contains(display) }
    func builtinDisplayID() -> CGDirectDisplayID? { builtin }
    func isOnline(_ display: CGDirectDisplayID) -> Bool { isOnlineResult }
    func resetTopology(mainDisplay: CGDirectDisplayID) -> Bool {
        resetTopologyCalls.append(mainDisplay)
        return resetTopologyResult
    }
}

final class SessionControllerTests: XCTestCase {
    var system: MockDisplaySystem!
    var settings: SettingsStore!
    var controller: SessionController!

    let glasses = GlassesInfo(displayID: 5, vendorID: 13895, productID: 16640,
                              name: "XREAL One Pro",
                              native: ModeSpec(width: 3840, height: 1080, refresh: 60))

    override func setUp() {
        let defaults = UserDefaults(suiteName: "xfake-session-tests")!
        defaults.removePersistentDomain(forName: "xfake-session-tests")
        system = MockDisplaySystem()
        settings = SettingsStore(defaults: defaults)
        controller = SessionController(system: system, settings: settings)
    }

    override func tearDown() {
        UserDefaults(suiteName: "xfake-session-tests")?
            .removePersistentDomain(forName: "xfake-session-tests")
    }

    func testGlassesAppearCreatesAspectMatchedVirtual() {
        controller.handle(.glassesAppeared(glasses))
        XCTAssertEqual(controller.state, .virtualCreating)
        XCTAssertEqual(system.createdConfigs.count, 1)
        let config = system.createdConfigs[0]
        XCTAssertEqual(config.vendorID, 13895)   // copied from glasses for persistence
        XCTAssertEqual(config.modes.first, glasses.native)
        XCTAssertEqual(config.modes.count, 28)
    }

    func testVirtualOnlineMirrorsSetsMainAndAppliesPreference() {
        settings.setPreferredMode(ModeSpec(width: 4160, height: 1170, refresh: 60),
                                  for: AspectRatio(of: glasses.native))
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        XCTAssertEqual(controller.state, .mirrored(virtual: 100, glasses: 5))
        XCTAssertEqual(system.mirrors.first?.master, 100)
        XCTAssertEqual(system.mirrors.first?.mirror, 5)
        XCTAssertEqual(system.mains, [100])
        XCTAssertEqual(system.appliedModes.first?.1, ModeSpec(width: 4160, height: 1170, refresh: 60))
    }

    func testUnrelatedVirtualOnlineIsIgnored() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(999))
        XCTAssertEqual(controller.state, .virtualCreating)
        XCTAssertTrue(system.mirrors.isEmpty)
    }

    func testDisappearTearsDownAndRestoresBuiltinMain() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        controller.handle(.glassesDisappeared(5))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(system.unmirrors, [5])
        XCTAssertEqual(system.mains.last, 1) // builtin
    }

    func testCreateFailureRetriesOnceThenErrors() {
        system.failCreates = 2
        controller.handle(.glassesAppeared(glasses))
        XCTAssertEqual(system.createdConfigs.count, 2)
        guard case .error = controller.state else { return XCTFail("expected error state") }
    }

    func testDisabledDoesNotCreate() {
        settings.isEnabled = false
        controller.handle(.glassesAppeared(glasses))
        XCTAssertEqual(controller.state, .glassesPresent)
        XCTAssertTrue(system.createdConfigs.isEmpty)
    }

    func testEnableWhileGlassesPresentStartsSession() {
        settings.isEnabled = false
        controller.handle(.glassesAppeared(glasses))
        settings.isEnabled = true
        controller.handle(.enabledChanged(true))
        XCTAssertEqual(controller.state, .virtualCreating)
    }

    func testDisableWhileMirroredTearsDown() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        settings.isEnabled = false
        controller.handle(.enabledChanged(false))
        XCTAssertEqual(controller.state, .glassesPresent)
        XCTAssertEqual(system.unmirrors, [5])
    }

    func testModeChangeRebuildsVirtualAtNewAspect() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        let sixteenNine = GlassesInfo(displayID: 5, vendorID: 13895, productID: 16640,
                                      name: "XREAL One Pro",
                                      native: ModeSpec(width: 1920, height: 1080, refresh: 120))
        system.nextVirtualID = 101
        controller.handle(.glassesModeChanged(sixteenNine))
        XCTAssertEqual(system.unmirrors, [5])
        XCTAssertEqual(system.createdConfigs.count, 2)
        XCTAssertEqual(system.createdConfigs[1].modes.first, sixteenNine.native)
        controller.handle(.virtualOnline(101))
        XCTAssertEqual(controller.state, .mirrored(virtual: 101, glasses: 5))
    }

    func testRepairReestablishesBrokenMirror() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        system.mirroredIDs.removeAll() // simulate wake breaking the mirror set
        controller.handle(.reconfigured)
        XCTAssertEqual(system.mirrors.count, 2, "repair should re-mirror")
    }

    // MARK: - Review findings (C1, I1-I5, M2, M5, M6)

    func testDuplicateGlassesAppearedWhileMirroredIsIgnored() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        controller.handle(.glassesAppeared(glasses)) // watcher rescan duplicate
        XCTAssertEqual(system.createdConfigs.count, 1, "duplicate must not create a second virtual")
        XCTAssertEqual(controller.state, .mirrored(virtual: 100, glasses: 5))
        XCTAssertTrue(system.unmirrors.isEmpty)
    }

    func testGlassesAppearedWithDifferentIDWhileMirroredRebuildsSession() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        let other = GlassesInfo(displayID: 6, vendorID: 13895, productID: 16640,
                                name: "XREAL One Pro",
                                native: ModeSpec(width: 3840, height: 1080, refresh: 60))
        controller.handle(.glassesAppeared(other))
        XCTAssertEqual(system.unmirrors, [5], "old session must be torn down first")
        XCTAssertEqual(system.createdConfigs.count, 2)
        XCTAssertEqual(controller.state, .virtualCreating)
        controller.handle(.virtualOnline(101))
        XCTAssertEqual(controller.state, .mirrored(virtual: 101, glasses: 6))
    }

    func testVirtualTerminatedWithMatchingIDWhileMirroredErrors() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        system.terminations.last?(100) // WindowServer kills the live display
        guard case .error = controller.state else { return XCTFail("expected error state") }
        XCTAssertNil(controller.virtualDisplayID)
    }

    func testVirtualTerminatedWhileCreatingErrorsInsteadOfSticking() {
        controller.handle(.glassesAppeared(glasses))
        XCTAssertEqual(controller.state, .virtualCreating)
        system.terminations.last?(100) // terminated before ever reporting online
        guard case .error = controller.state else { return XCTFail("expected error state, not stuck .virtualCreating") }
    }

    func testVirtualTerminatedWithStaleIDIsIgnored() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        controller.handle(.virtualTerminated(999)) // callback from an old, replaced display
        XCTAssertEqual(controller.state, .mirrored(virtual: 100, glasses: 5))
        XCTAssertNotNil(controller.virtualDisplayID)
    }

    func testGlassesDisappearedWithNonMatchingIDIsIgnored() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        controller.handle(.glassesDisappeared(99))
        XCTAssertEqual(controller.state, .mirrored(virtual: 100, glasses: 5))
        XCTAssertTrue(system.unmirrors.isEmpty)
    }

    func testMirrorFailureEntersErrorState() {
        system.mirrorResult = false
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        guard case .error = controller.state else { return XCTFail("expected error state") }
        XCTAssertNil(controller.virtualDisplayID, "failed session must release the virtual display")
    }

    func testTeardownWhenInactiveTouchesNoDisplayState() {
        settings.isEnabled = false
        controller.handle(.glassesAppeared(glasses))
        XCTAssertEqual(controller.state, .glassesPresent)
        controller.handle(.glassesDisappeared(5))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(system.unmirrors.isEmpty, "no live virtual -> never unmirror")
        XCTAssertTrue(system.mains.isEmpty, "no live virtual -> never touch main display")
    }

    func testReentrantEventDuringTeardownIsDeferred() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        system.onUnmirror = { [weak self] in
            // CG reconfiguration callback firing from inside the teardown transaction
            self?.controller.handle(.reconfigured)
        }
        controller.handle(.glassesDisappeared(5))
        XCTAssertEqual(controller.state, .idle, "teardown must run to completion")
        XCTAssertEqual(system.mirrors.count, 1, "deferred repair must not re-mirror a torn-down session")
    }

    func testEnabledChangedRecoversFromErrorState() {
        system.failCreates = 2
        controller.handle(.glassesAppeared(glasses))
        guard case .error = controller.state else { return XCTFail("expected error state") }
        controller.handle(.enabledChanged(true))
        XCTAssertEqual(controller.state, .virtualCreating, "enable should retry from error when glasses are present")
    }

    // MARK: - Review residuals

    func testDisableDuringVirtualCreatingTearsDownWithoutUnmirror() {
        controller.handle(.glassesAppeared(glasses))
        XCTAssertEqual(controller.state, .virtualCreating)
        settings.isEnabled = false
        controller.handle(.enabledChanged(false))
        XCTAssertEqual(controller.state, .glassesPresent)
        XCTAssertTrue(system.unmirrors.isEmpty, "never mirrored -> unmirror must not be called")
        XCTAssertNil(controller.virtualDisplayID, "the never-mirrored virtual handle must still be released")
    }

    func testRepairSkipsReMirrorWhenDisplaysReportOffline() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        XCTAssertEqual(system.mirrors.count, 1)
        system.mirroredIDs.removeAll() // simulate wake breaking the mirror set
        system.isOnlineResult = false
        controller.handle(.reconfigured)
        XCTAssertEqual(system.mirrors.count, 1, "isOnline() == false must short-circuit repair before re-mirroring")
    }

    // MARK: - Fix 1: apply native by default

    func testFirstRunAppliesNativeModeWhenNoPreferenceStored() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        XCTAssertEqual(system.appliedModes.first?.1, glasses.native, "first run should apply native, the sharpest mode")
    }

    // MARK: - Fix 4: adopt resolution changes made in System Settings

    func testReconfiguredWhileMirroredAdoptsInLadderCurrentMode() {
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        let inLadder = ModeSpec(width: 4160, height: 1170, refresh: 60)
        system.currentModeResult = inLadder
        controller.handle(.reconfigured)
        XCTAssertEqual(settings.preferredMode(for: AspectRatio(of: glasses.native)), inLadder)
    }

    func testReconfiguredWhileMirroredClearsPreferenceWhenCurrentModeOutsideLadder() {
        let aspect = AspectRatio(of: glasses.native)
        settings.setPreferredMode(ModeSpec(width: 4160, height: 1170, refresh: 60), for: aspect)
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        system.currentModeResult = ModeSpec(width: 9999, height: 9999, refresh: 60) // not on the ladder
        controller.handle(.reconfigured)
        XCTAssertNil(settings.preferredMode(for: aspect), "an out-of-ladder mode must clear the stored preference")
    }

    func testReconfiguredWhileMirroredMakesNoChangeWhenCurrentModeAlreadyMatchesPreference() {
        let aspect = AspectRatio(of: glasses.native)
        let inLadder = ModeSpec(width: 4160, height: 1170, refresh: 60)
        settings.setPreferredMode(inLadder, for: aspect)
        controller.handle(.glassesAppeared(glasses))
        controller.handle(.virtualOnline(100))
        system.currentModeResult = inLadder
        controller.handle(.reconfigured)
        XCTAssertEqual(settings.preferredMode(for: aspect), inLadder)
    }

    func testReconfiguredWhileNotMirroredStoresNoPreference() {
        let aspect = AspectRatio(of: glasses.native)
        system.currentModeResult = ModeSpec(width: 4160, height: 1170, refresh: 60)
        controller.handle(.reconfigured) // still .idle — no glasses, no virtual display
        XCTAssertNil(settings.preferredMode(for: aspect))
    }

    // MARK: - Fix 3: `xfake reset` topology reset

    func testResetTopologyIsCalledWithRequestedMainDisplay() {
        XCTAssertTrue(system.resetTopology(mainDisplay: 1))
        XCTAssertEqual(system.resetTopologyCalls, [1])
    }

    func testResetTopologyPropagatesFailure() {
        system.resetTopologyResult = false
        XCTAssertFalse(system.resetTopology(mainDisplay: 1))
    }
}
