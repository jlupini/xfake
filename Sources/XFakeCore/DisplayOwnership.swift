import CoreGraphics

/// djb2. Stable across launches so macOS keeps remembering the virtual
/// display's arrangement, mode and colour profile.
public func xfakeStableSerial(for identity: String) -> UInt32 {
    var hash: UInt32 = 5381
    for byte in identity.utf8 { hash = hash &* 33 &+ UInt32(byte) }
    return hash
}

public extension DisplayInfo {
    /// Whether this display is one xfake created.
    ///
    /// Our virtual displays deliberately copy the glasses' vendor and product
    /// ID so macOS persists their arrangement, which makes vendor matching
    /// alone ambiguous. They are told apart by their serial, which we derive
    /// from that same identity — real XREAL hardware reports 0.
    var isXfakeVirtual: Bool {
        serialNumber != 0 && serialNumber == xfakeStableSerial(for: "\(vendorID):\(productID)")
    }
}

/// Picks the glasses out of the online displays.
///
/// Skipping xfake's own virtual displays matters most in the window where the
/// live handle has already been released but WindowServer still lists the
/// dying display: without this, that corpse matches on vendor ID, the watcher
/// reports it as newly-appeared glasses, and the next session is built around
/// the previous session's virtual display — inheriting its enormous mode list
/// as a supposed panel "native" size.
public func selectGlassesDisplay(from candidates: [DisplayInfo],
                                 vendorIDs: Set<UInt32>,
                                 liveVirtualID: CGDirectDisplayID?) -> DisplayInfo? {
    candidates.first {
        $0.id != liveVirtualID && vendorIDs.contains($0.vendorID) && !$0.isXfakeVirtual
    }
}
