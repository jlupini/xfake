import AppKit
import CoreGraphics
import Dispatch

/// Watches display reconfigurations and translates them into DisplayEvents.
/// Debounces 500ms because hotplug fires bursts of callbacks.
///
/// CGDisplayRegisterReconfigurationCallback delivery cannot be relied on
/// alone in a headless CLI process (observed live: the callback simply did
/// not fire for a mode change the glasses made on their own). A 1-second
/// poll is the authoritative rescan source; the CG callback's debounced scan
/// is kept for fast response when it does arrive, but correctness no longer
/// depends on it.
public final class GlassesWatcher {
    public var onEvent: ((DisplayEvent) -> Void)?

    private let vendorIDs: Set<UInt32>
    private var knownGlasses: GlassesInfo?
    private var ownVirtualID: () -> CGDirectDisplayID?
    private var pendingScan: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?

    /// ownVirtualID lets the watcher recognize the SessionController's own
    /// virtual display coming online (-> .virtualOnline) vs other changes.
    public init(vendorIDs: Set<UInt32>, ownVirtualID: @escaping () -> CGDirectDisplayID?) {
        self.vendorIDs = vendorIDs
        self.ownVirtualID = ownVirtualID
    }

    public func start() {
        CGDisplayRegisterReconfigurationCallback(watcherCallback,
            Unmanaged.passUnretained(self).toOpaque())
        startPolling()
        scan(source: "start")
    }

    public func stop() {
        CGDisplayRemoveReconfigurationCallback(watcherCallback,
            Unmanaged.passUnretained(self).toOpaque())
        pollTimer?.cancel()
        pollTimer = nil
    }

    deinit {
        // The CG callback holds an unretained pointer to self; deallocating
        // without unregistering would be a use-after-free on the next
        // reconfiguration. Removing a never-registered callback is harmless.
        stop()
        pendingScan?.cancel()
    }

    /// DispatchSourceTimer (not Timer, which needs an active run-loop mode
    /// that a headless CLI process may never enter) on the main queue, since
    /// scan() must only ever run on the main queue (SessionController
    /// asserts .onQueue(.main)).
    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.scan(source: "poll") }
        timer.resume()
        pollTimer = timer
    }

    fileprivate func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan(source: "cg-callback") }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    public func scan() {
        scan(source: "manual")
    }

    private func scan(source: String) {
        let online = onlineDisplayIDs()
        let virtualID = ownVirtualID()
        xfakeTrace("scan source=\(source) online=\(online) virtualID=\(virtualID.map(String.init) ?? "nil")")

        if let virtualID, online.contains(virtualID) {
            xfakeTrace("event: .virtualOnline(\(virtualID))")
            onEvent?(.virtualOnline(virtualID))
        }

        // The virtual display deliberately copies the glasses' vendorID (so
        // macOS persists arrangement), so it must be excluded here or the
        // watcher would match xfake's own virtual display as the glasses.
        let found = online.first { $0 != virtualID && vendorIDs.contains(CGDisplayVendorNumber($0)) }
        switch (knownGlasses, found) {
        case (nil, .some(let id)):
            if let info = glassesInfo(id) {
                knownGlasses = info
                xfakeTrace("event: .glassesAppeared(\(info))")
                onEvent?(.glassesAppeared(info))
            }
        case (.some(let known), nil):
            knownGlasses = nil
            xfakeTrace("event: .glassesDisappeared(\(known.displayID))")
            onEvent?(.glassesDisappeared(known.displayID))
        case (.some(let known), .some(let id)):
            if var info = glassesInfo(id) {
                // While mirrored, NSScreen omits the mirrored display and the
                // name lookup falls back to "Display N"; carry the known name
                // forward so the rebuilt virtual display keeps its identity.
                if info.displayID == known.displayID, info.name == "Display \(id)" {
                    info = GlassesInfo(displayID: info.displayID, vendorID: info.vendorID,
                                       productID: info.productID, name: known.name,
                                       native: info.native)
                }
                // A new displayID (same-vendor replug) needs the same
                // teardown-and-rebuild as an aspect change.
                if info.displayID != known.displayID || info.native != known.native {
                    knownGlasses = info
                    xfakeTrace("event: .glassesModeChanged(\(info))")
                    onEvent?(.glassesModeChanged(info))
                } else {
                    xfakeTrace("event: .reconfigured")
                    onEvent?(.reconfigured)
                }
            } else {
                xfakeTrace("event: .reconfigured")
                onEvent?(.reconfigured)
            }
        case (nil, nil):
            break
        }
    }

    private func glassesInfo(_ id: CGDirectDisplayID) -> GlassesInfo? {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let raw = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] ?? []).map {
            RawMode(width: $0.width, height: $0.height,
                    pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight,
                    refresh: $0.refreshRate)
        }
        guard let native = NativeMode.select(from: raw) else { return nil }
        var name = "Display \(id)"
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               num == id {
                name = screen.localizedName
            }
        }
        return GlassesInfo(displayID: id, vendorID: CGDisplayVendorNumber(id),
                           productID: CGDisplayModelNumber(id), name: name, native: native)
    }
}

private func watcherCallback(display: CGDirectDisplayID,
                             flags: CGDisplayChangeSummaryFlags,
                             userInfo: UnsafeMutableRawPointer?) {
    xfakeTrace("cg-callback display=\(display) flags=\(flags.rawValue)")
    guard let userInfo else { return }
    let watcher = Unmanaged<GlassesWatcher>.fromOpaque(userInfo).takeUnretainedValue()
    watcher.scheduleScan()
}
