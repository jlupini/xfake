import Foundation

/// A diagnostic snapshot of how sharp the hardware-mirrored image on the
/// glasses' physical panel currently is. Mirroring downsamples the ENTIRE
/// virtual framebuffer to the panel's native resolution, so sharpness is
/// purely a function of the ratio between the virtual display's current
/// logical size and the panel's native size — not anything xfake can fix
/// after the fact, only something it can report honestly.
public struct SharpnessReport {
    public let panelNative: ModeSpec
    public let currentLogical: ModeSpec

    public init(panelNative: ModeSpec, currentLogical: ModeSpec) {
        self.panelNative = panelNative
        self.currentLogical = currentLogical
    }

    public var ratio: Double {
        Double(currentLogical.width) / Double(panelNative.width)
    }

    /// The physical panel height, in pixels, that a 13pt glyph is downscaled to.
    public var glyphPixels: Double {
        13 / ratio
    }

    /// Keyed off glyph pixels, not the ratio: that figure is panel-independent,
    /// and live testing calibrated the comfortable boundary near 9-10px — far
    /// more permissive than the ratio alone suggests, because the framebuffer is
    /// 2x supersampled and the glasses' optics soften below panel-native anyway.
    public var verdict: String {
        if glyphPixels >= 12.5 { return "1:1 or better — sharpest possible" }
        else if glyphPixels >= 10.0 { return "crisp" }
        else if glyphPixels >= 9.0 { return "slightly soft" }
        else { return "soft — text may be hard to read" }
    }

    public var summary: String {
        let ratioStr = String(format: "%.2f", ratio)
        let glyphStr = String(format: "%.1f", glyphPixels)
        return "panel native \(panelNative.width)×\(panelNative.height), showing "
            + "\(currentLogical.width)×\(currentLogical.height) logical → \(ratioStr)× "
            + "(\(verdict); a 13pt glyph lands on \(glyphStr) panel pixels). "
            + "Perceived sharpness also depends on the glasses' optics — trust your eyes over this label."
    }
}
