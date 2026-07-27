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
    /// Mirrors `mirror` onto `master` AND makes `master` the main display in a
    /// single WindowServer transaction (no intermediate flicker state).
    func mirrorAndSetMain(master: CGDirectDisplayID, mirror: CGDirectDisplayID) -> Bool
    func unmirror(_ display: CGDirectDisplayID) -> Bool
    func setMain(_ display: CGDirectDisplayID) -> Bool
    func applyMode(_ display: CGDirectDisplayID, mode: ModeSpec) -> Bool
    /// The display's current logical mode (width/height + refresh), or nil if
    /// it cannot be read. Used to detect resolution changes made outside
    /// xfake (e.g. via System Settings) so xfake can adopt them instead of
    /// overriding them with a stale stored preference.
    func currentMode(of display: CGDirectDisplayID) -> ModeSpec?
    func isMirrored(_ display: CGDirectDisplayID) -> Bool
    func builtinDisplayID() -> CGDirectDisplayID?
    func isOnline(_ display: CGDirectDisplayID) -> Bool
    /// Un-mirrors every currently online display and makes `mainDisplay` the
    /// main display, all in a single WindowServer transaction. Used by
    /// `xfake reset` to recover from a leftover mirror topology (e.g. a prior
    /// xfake process that died without tearing down) without the flicker or
    /// intermediate states multiple transactions would cause.
    func resetTopology(mainDisplay: CGDirectDisplayID) -> Bool
}
