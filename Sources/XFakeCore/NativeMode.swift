/// A display mode as reported by CGDisplayCopyAllDisplayModes, decoupled from
/// CGDisplayMode (which cannot be constructed in tests).
public struct RawMode: Equatable {
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refresh: Double

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refresh: Double) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refresh = refresh
    }
}

public enum NativeMode {
    /// The native panel mode: the 1x mode (pixel == logical) with the most
    /// pixels, at its highest refresh rate. Exact ties (same pixel count and
    /// refresh) resolve arbitrarily by list order.
    public static func select(from modes: [RawMode]) -> ModeSpec? {
        modes.filter { $0.pixelWidth == $0.width && $0.pixelHeight == $0.height }
            .max { a, b in
                (a.pixelWidth * a.pixelHeight, a.refresh) < (b.pixelWidth * b.pixelHeight, b.refresh)
            }
            .map { ModeSpec(width: $0.width, height: $0.height, refresh: $0.refresh) }
    }
}
