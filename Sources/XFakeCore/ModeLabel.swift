import Foundation

/// Human label for a virtual-display mode, stated as a tradeoff rather than a
/// verdict: how much extra desktop space it buys, and how many physical panel
/// pixels a 13pt glyph ends up occupying once the mirror downsamples it.
///
/// Panel pixels per glyph is the panel-independent metric — live testing put the
/// comfortable boundary near 9-10px, well below what the raw ratio implies,
/// because the framebuffer is 2x supersampled and the glasses' optics are the
/// real limiter. Only genuinely marginal modes get a warning; the rest is the
/// user's call.
public func modeLabel(for mode: ModeSpec, native: ModeSpec) -> String {
    let dims = "\(mode.width) × \(mode.height)"
    guard mode.width != native.width || mode.height != native.height else {
        return "\(dims) · native · sharpest"
    }
    let ratio = Double(mode.width) / Double(native.width)
    let percent = Int((ratio - 1) * 100 + 0.5)
    let glyphPixels = 13 / ratio
    let pixelStr = String(format: "%.1f", glyphPixels)
    let warning = glyphPixels < 9.0 ? " · may look soft" : ""
    return "\(dims) · +\(percent)% space · \(pixelStr)px text\(warning)"
}

/// The scale presets offered in the menu bar, snapped to the nearest ladder
/// entry. A 20-30 entry ladder is unusable in a submenu; these are the choices
/// worth reasoning about, and the full ladder stays available in System Settings
/// for fine-tuning. Native always leads.
public func modePresets(ladder: [ModeSpec], native: ModeSpec) -> [ModeSpec] {
    guard !ladder.isEmpty else { return [] }
    let scales = [1.0, 1.10, 1.25, 1.5, 1.75, 2.0]
    var presets: [ModeSpec] = []
    for scale in scales {
        let targetWidth = Double(native.width) * scale
        guard let nearest = ladder.min(by: {
            abs(Double($0.width) - targetWidth) < abs(Double($1.width) - targetWidth)
        }) else { continue }
        if !presets.contains(nearest) { presets.append(nearest) }
    }
    return presets
}
