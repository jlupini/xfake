import CoreGraphics

public protocol VirtualHandle: AnyObject {
    var displayID: CGDirectDisplayID { get }
}

public struct VirtualDisplayConfig {
    public let name: String
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNum: UInt32
    public let sizeInMM: CGSize
    public let modes: [ModeSpec]

    public init(name: String, vendorID: UInt32, productID: UInt32, serialNum: UInt32,
                sizeInMM: CGSize, modes: [ModeSpec]) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNum = serialNum
        self.sizeInMM = sizeInMM
        self.modes = modes
    }
}

public protocol DisplaySystem: AnyObject {
    /// nil on failure. Releasing the handle destroys the display.
    /// onTermination receives the terminated display's ID so stale callbacks
    /// from an already-replaced virtual display can be ignored.
    func createVirtualDisplay(_ config: VirtualDisplayConfig, onTermination: @escaping (CGDirectDisplayID) -> Void) -> VirtualHandle?
    /// Identity and role of every online display, for deciding mirror-set
    /// membership and listing displays in the UI.
    func onlineDisplays() -> [DisplayInfo]
    /// Declares the whole topology in one WindowServer transaction: `master`
    /// becomes the main display, every display in `mirrors` joins its mirror
    /// set, and any display that was mirroring `master` but is no longer
    /// wanted is released. Mirror sets between other displays are left alone.
    ///
    /// Declarative rather than incremental so a settings toggle, a session
    /// start and a post-wake repair all run the same single code path and
    /// converge on the same end state.
    func applyMirrorTopology(master: CGDirectDisplayID, mirrors: [CGDirectDisplayID]) -> Bool
    func unmirror(_ display: CGDirectDisplayID) -> Bool
    func setMain(_ display: CGDirectDisplayID) -> Bool
    func applyMode(_ display: CGDirectDisplayID, mode: ModeSpec) -> Bool
    /// The display's current logical mode (width/height + refresh), or nil if
    /// it cannot be read. Used to detect resolution changes made outside
    /// xfake (e.g. via System Settings) so xfake can adopt them instead of
    /// overriding them with a stale stored preference.
    func currentMode(of display: CGDirectDisplayID) -> ModeSpec?
    /// The display this one is mirroring, or nil if it is independent. More
    /// precise than a bare "is mirrored" flag: xfake must distinguish displays
    /// in ITS mirror set from ones in a set the user built themselves.
    func mirrorSource(of display: CGDirectDisplayID) -> CGDirectDisplayID?
    func builtinDisplayID() -> CGDirectDisplayID?
    func isOnline(_ display: CGDirectDisplayID) -> Bool
    /// Un-mirrors every currently online display and makes `mainDisplay` the
    /// main display, all in a single WindowServer transaction. Used by
    /// `xfake reset` to recover from a leftover mirror topology (e.g. a prior
    /// xfake process that died without tearing down) without the flicker or
    /// intermediate states multiple transactions would cause.
    func resetTopology(mainDisplay: CGDirectDisplayID) -> Bool
}
