import CoreGraphics

public let xrealVendorIDs: Set<UInt32> = [13895] // 0x3647 — XREAL

/// A logical (point) display mode. HiDPI backing is always 2x these dimensions.
public struct ModeSpec: Equatable, Hashable, Codable, CustomStringConvertible {
    public let width: Int
    public let height: Int
    public let refresh: Double

    public init(width: Int, height: Int, refresh: Double) {
        self.width = width
        self.height = height
        self.refresh = refresh
    }

    public var description: String { "\(width)x\(height)@\(Int(refresh))" }
}

/// Reduced aspect ratio, e.g. 32:9 or 16:9.
public struct AspectRatio: Equatable, Hashable, CustomStringConvertible {
    public let w: Int
    public let h: Int

    public init(of mode: ModeSpec) {
        precondition(mode.width > 0 && mode.height > 0, "invalid mode dimensions")
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = gcd(mode.width, mode.height)
        self.w = mode.width / g
        self.h = mode.height / g
    }

    public var description: String { "\(w):\(h)" }
}

/// A detected pair of glasses (or any managed physical display).
public struct GlassesInfo: Equatable {
    public let displayID: CGDirectDisplayID
    public let vendorID: UInt32
    public let productID: UInt32
    public let name: String
    public let native: ModeSpec

    public init(displayID: CGDirectDisplayID, vendorID: UInt32, productID: UInt32, name: String, native: ModeSpec) {
        self.displayID = displayID
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.native = native
    }
}

public enum DisplayEvent: Equatable {
    case glassesAppeared(GlassesInfo)
    case glassesModeChanged(GlassesInfo)
    case glassesDisappeared(CGDirectDisplayID)
    case virtualOnline(CGDirectDisplayID)
    case virtualTerminated(CGDirectDisplayID)
    case reconfigured
    case enabledChanged(Bool)
}

public enum SessionState: Equatable {
    case idle
    case glassesPresent           // glasses connected but app disabled
    case virtualCreating
    case mirrored(virtual: CGDirectDisplayID, glasses: CGDirectDisplayID)
    case error(String)
}
