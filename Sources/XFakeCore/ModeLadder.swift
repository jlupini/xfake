/// Generates the logical-resolution ladder for a virtual display matching the
/// glasses' native mode, from native up to 2x native at the exact aspect.
///
/// Two tiers, because sharpness decisions cluster near the bottom:
/// - **Fine** (1.0x-1.25x): steps of the reduced aspect unit, doubled while the
///   tier would exceed 16 entries, so the band where people actually settle is
///   finely adjustable. For 32:9 this keeps 4160x1170 — the mode BetterDisplay
///   users converge on.
/// - **Coarse** (1.25x-2.0x): 4x the fine step, keeping the wide-open end
///   browsable instead of flooding the list.
///
/// Both tiers are offsets from native, so every entry holds the exact aspect and
/// the 2x endpoint lands precisely.
///
/// Nothing is capped for sharpness reasons: mirroring downsamples the whole
/// framebuffer to the panel, but that framebuffer is 2x supersampled and the
/// glasses' optics soften below panel-native anyway, so mild downscale costs far
/// less than the raw ratio suggests. SharpnessReport and ModeLabel report the
/// tradeoff in panel pixels per glyph and let the user's eyes decide.
public enum ModeLadder {
    public static func generate(native: ModeSpec) -> [ModeSpec] {
        let aspect = AspectRatio(of: native)
        let fineBoundary = native.width + native.width / 4   // 1.25x
        let maxWidth = native.width * 2                      // 2.0x

        var fineW = aspect.w
        var fineH = aspect.h
        while (fineBoundary - native.width) / fineW > 16 {
            fineW *= 2
            fineH *= 2
        }
        let coarseW = fineW * 4
        let coarseH = fineH * 4

        func mode(_ steps: Int, _ stepW: Int, _ stepH: Int) -> ModeSpec {
            ModeSpec(width: native.width + steps * stepW,
                     height: native.height + steps * stepH,
                     refresh: native.refresh)
        }

        var modes: [ModeSpec] = []
        var step = 0
        while native.width + step * fineW <= fineBoundary {
            modes.append(mode(step, fineW, fineH))
            step += 1
        }
        // Coarse positions are a subset of fine positions (4x the step), so skip
        // any that the fine tier already covered.
        step = 1
        while native.width + step * coarseW <= maxWidth {
            if native.width + step * coarseW > fineBoundary {
                modes.append(mode(step, coarseW, coarseH))
            }
            step += 1
        }
        return modes
    }
}
