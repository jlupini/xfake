import XCTest
import CoreGraphics
@testable import XFakeCore

/// The virtual display copies the glasses' vendor and product ID, so telling
/// the two apart is load-bearing: get it wrong and xfake builds its next
/// session around its own previous virtual display.
final class DisplayOwnershipTests: XCTestCase {
    private func display(id: CGDirectDisplayID, vendor: UInt32 = 13895,
                         product: UInt32 = 16640, serial: UInt32) -> DisplayInfo {
        DisplayInfo(id: id, name: "", vendorID: vendor, productID: product,
                    serialNumber: serial, isBuiltin: false)
    }

    private var realGlasses: DisplayInfo { display(id: 2, serial: 0) }
    private var ourVirtual: DisplayInfo {
        display(id: 10, serial: xfakeStableSerial(for: "13895:16640"))
    }

    // MARK: - Fingerprint

    func testSerialMatchesTheValueObservedOnRealHardware() {
        XCTAssertEqual(xfakeStableSerial(for: "13895:16640"), 3503522666,
                       "the fingerprint must keep matching displays created by earlier builds")
    }

    func testOurVirtualDisplayIsRecognisedByItsDerivedSerial() {
        XCTAssertTrue(ourVirtual.isXfakeVirtual)
    }

    func testRealGlassesReportingSerialZeroAreNotMistakenForOurs() {
        XCTAssertFalse(realGlasses.isXfakeVirtual)
    }

    func testAnUnrelatedSerialIsNotOurs() {
        XCTAssertFalse(display(id: 3, serial: 12345).isXfakeVirtual)
    }

    func testTheFingerprintIsSpecificToTheIdentityItWasDerivedFrom() {
        let differentPanel = display(id: 4, vendor: 13895, product: 99999,
                                     serial: xfakeStableSerial(for: "13895:16640"))
        XCTAssertFalse(differentPanel.isXfakeVirtual,
                       "a serial only counts as ours against its own vendor:product")
    }

    // MARK: - Selection

    func testPicksTheRealGlassesOverOurVirtualDisplay() {
        let picked = selectGlassesDisplay(from: [ourVirtual, realGlasses],
                                          vendorIDs: xrealVendorIDs, liveVirtualID: 10)
        XCTAssertEqual(picked?.id, 2)
    }

    /// The live-captured regression: during teardown the handle is already nil
    /// while WindowServer still lists the dying display. It used to match on
    /// vendor ID and get reported as newly-connected glasses, so the next
    /// session was built from its 7680x4320 mode list.
    func testIgnoresOurDyingVirtualDisplayAfterTheHandleIsReleased() {
        XCTAssertNil(selectGlassesDisplay(from: [ourVirtual], vendorIDs: xrealVendorIDs,
                                          liveVirtualID: nil),
                     "a released-but-still-online virtual display is not glasses")
    }

    func testStillPicksTheGlassesWhileOurVirtualDisplayLingers() {
        let picked = selectGlassesDisplay(from: [ourVirtual, realGlasses],
                                          vendorIDs: xrealVendorIDs, liveVirtualID: nil)
        XCTAssertEqual(picked?.id, 2)
    }

    func testIgnoresTheLiveVirtualDisplayById() {
        // Belt and braces: the id check still holds even for a display whose
        // serial somehow fails the fingerprint.
        let oddVirtual = display(id: 10, serial: 7)
        XCTAssertNil(selectGlassesDisplay(from: [oddVirtual], vendorIDs: xrealVendorIDs,
                                          liveVirtualID: 10))
    }

    func testIgnoresDisplaysFromOtherVendors() {
        let dell = DisplayInfo(id: 9, name: "", vendorID: 4268, productID: 16498,
                               serialNumber: 1234, isBuiltin: false)
        XCTAssertNil(selectGlassesDisplay(from: [dell], vendorIDs: xrealVendorIDs,
                                          liveVirtualID: nil))
    }

    func testReturnsNilWhenNothingIsConnected() {
        XCTAssertNil(selectGlassesDisplay(from: [], vendorIDs: xrealVendorIDs, liveVirtualID: nil))
    }
}
