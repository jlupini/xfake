import CoreGraphics
import CGVirtualDisplayBridge
import os.log

/// All currently online display IDs (shared by RealDisplaySystem and the CLI).
public func onlineDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    guard count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

final class RealVirtualHandle: VirtualHandle {
    let displayID: CGDirectDisplayID
    private let owner: XFVirtualDisplay // strong ref keeps the display alive
    init(_ owner: XFVirtualDisplay) {
        self.owner = owner
        self.displayID = owner.displayID
    }
}

public final class RealDisplaySystem: DisplaySystem {
    private static let log = Logger(subsystem: "com.jlupini.xfake", category: "display")

    /// Session scope, deliberately NOT `.permanently`: our virtual displays are
    /// ephemeral (they die with the process), so writing topology changes to
    /// macOS's on-disk display config leaves it holding instructions about a
    /// display that no longer exists — which macOS then replays whenever a
    /// matching display identity reappears. xfake keeps its own resolution
    /// memory in SettingsStore and re-applies it deliberately instead.
    /// `resetTopology` is the one exception: it uses `.permanently` on purpose,
    /// to overwrite a polluted persisted config with a clean one.
    private static let scope = CGConfigureOption.forSession

    public init() {}

    public func createVirtualDisplay(_ config: VirtualDisplayConfig,
                                     onTermination: @escaping (CGDirectDisplayID) -> Void) -> VirtualHandle? {
        let modes = config.modes.map {
            XFModeSpec(width: UInt32($0.width), height: UInt32($0.height), refreshRate: $0.refresh)
        }
        // The bridge's termination handler takes no arguments; a reference box
        // lets the closure report the display ID assigned after init returns.
        final class IDBox { var id: CGDirectDisplayID = 0 }
        let box = IDBox()
        guard let display = XFVirtualDisplay(
            name: config.name, vendorID: config.vendorID, productID: config.productID,
            serialNum: config.serialNum, sizeInMM: config.sizeInMM, modes: modes,
            terminationHandler: { onTermination(box.id) }
        ) else {
            Self.log.error("createVirtualDisplay: XFVirtualDisplay init/applySettings failed for \(config.name, privacy: .public)")
            return nil
        }
        box.id = display.displayID
        return RealVirtualHandle(display)
    }

    public func mirrorAndSetMain(master: CGDirectDisplayID, mirror: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else {
            Self.log.error("mirrorAndSetMain: CGBeginDisplayConfiguration failed (\(begin.rawValue))")
            return false
        }
        let mirrorErr = CGConfigureDisplayMirrorOfDisplay(config, mirror, master)
        let originErr = CGConfigureDisplayOrigin(config, master, 0, 0)
        guard mirrorErr == .success, originErr == .success else {
            Self.log.error("mirrorAndSetMain: configure failed (mirror=\(mirrorErr.rawValue) origin=\(originErr.rawValue))")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let complete = CGCompleteDisplayConfiguration(config, Self.scope)
        guard complete == .success else {
            Self.log.error("mirrorAndSetMain: CGCompleteDisplayConfiguration failed (\(complete.rawValue))")
            return false
        }
        return true
    }

    public func unmirror(_ display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else {
            Self.log.error("unmirror: CGBeginDisplayConfiguration failed (\(begin.rawValue))")
            return false
        }
        let mirrorErr = CGConfigureDisplayMirrorOfDisplay(config, display, kCGNullDirectDisplay)
        guard mirrorErr == .success else {
            Self.log.error("unmirror: CGConfigureDisplayMirrorOfDisplay failed (\(mirrorErr.rawValue))")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let complete = CGCompleteDisplayConfiguration(config, Self.scope)
        guard complete == .success else {
            Self.log.error("unmirror: CGCompleteDisplayConfiguration failed (\(complete.rawValue))")
            return false
        }
        return true
    }

    public func setMain(_ display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else {
            Self.log.error("setMain: CGBeginDisplayConfiguration failed (\(begin.rawValue))")
            return false
        }
        let originErr = CGConfigureDisplayOrigin(config, display, 0, 0)
        guard originErr == .success else {
            Self.log.error("setMain: CGConfigureDisplayOrigin failed (\(originErr.rawValue))")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let complete = CGCompleteDisplayConfiguration(config, Self.scope)
        guard complete == .success else {
            Self.log.error("setMain: CGCompleteDisplayConfiguration failed (\(complete.rawValue))")
            return false
        }
        return true
    }

    public func applyMode(_ display: CGDirectDisplayID, mode: ModeSpec) -> Bool {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(display, opts) as? [CGDisplayMode],
              let target = all.first(where: {
                  $0.width == mode.width && $0.height == mode.height
                      && $0.pixelWidth == mode.width * 2 // HiDPI variant
                      && abs($0.refreshRate - mode.refresh) < 1.0
              })
        else {
            Self.log.error("applyMode: no HiDPI mode \(mode.description, privacy: .public) on display \(display)")
            return false
        }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else {
            Self.log.error("applyMode: CGBeginDisplayConfiguration failed (\(begin.rawValue))")
            return false
        }
        let modeErr = CGConfigureDisplayWithDisplayMode(config, display, target, nil)
        guard modeErr == .success else {
            Self.log.error("applyMode: CGConfigureDisplayWithDisplayMode failed (\(modeErr.rawValue))")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let complete = CGCompleteDisplayConfiguration(config, Self.scope)
        guard complete == .success else {
            Self.log.error("applyMode: CGCompleteDisplayConfiguration failed (\(complete.rawValue))")
            return false
        }
        return true
    }

    public func currentMode(of display: CGDirectDisplayID) -> ModeSpec? {
        guard let mode = CGDisplayCopyDisplayMode(display) else { return nil }
        return ModeSpec(width: mode.width, height: mode.height, refresh: mode.refreshRate)
    }

    public func isMirrored(_ display: CGDirectDisplayID) -> Bool {
        CGDisplayMirrorsDisplay(display) != kCGNullDirectDisplay
    }

    public func builtinDisplayID() -> CGDirectDisplayID? {
        onlineDisplayIDs().first { CGDisplayIsBuiltin($0) == 1 }
    }

    public func isOnline(_ display: CGDirectDisplayID) -> Bool {
        onlineDisplayIDs().contains(display)
    }

    public func resetTopology(mainDisplay: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else {
            Self.log.error("resetTopology: CGBeginDisplayConfiguration failed (\(begin.rawValue))")
            return false
        }
        for display in onlineDisplayIDs() {
            let mirrorErr = CGConfigureDisplayMirrorOfDisplay(config, display, kCGNullDirectDisplay)
            guard mirrorErr == .success else {
                Self.log.error("resetTopology: CGConfigureDisplayMirrorOfDisplay failed for \(display) (\(mirrorErr.rawValue))")
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        let originErr = CGConfigureDisplayOrigin(config, mainDisplay, 0, 0)
        guard originErr == .success else {
            Self.log.error("resetTopology: CGConfigureDisplayOrigin failed (\(originErr.rawValue))")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        guard complete == .success else {
            Self.log.error("resetTopology: CGCompleteDisplayConfiguration failed (\(complete.rawValue))")
            return false
        }
        return true
    }
}
