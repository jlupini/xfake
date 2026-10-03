import CoreGraphics
import Dispatch
import os.log

/// Sole orchestrator of WindowServer operations. Feed it DisplayEvents from
/// one serial context (main thread); it never blocks. Re-entrant calls to
/// handle(_:) — e.g. CG reconfiguration callbacks firing from inside
/// CGCompleteDisplayConfiguration during a teardown — are queued and processed
/// after the current transition finishes, so every transition runs to
/// completion against a consistent state.
public final class SessionController {
    private static let log = Logger(subsystem: "com.jlupini.xfake", category: "session")

    public private(set) var state: SessionState = .idle
    public var onStateChange: ((SessionState) -> Void)?

    private let system: DisplaySystem
    private let settings: SettingsStore
    private var virtualHandle: VirtualHandle?
    private var glasses: GlassesInfo?

    private var pendingEvents: [DisplayEvent] = []
    private var isProcessing = false

    public init(system: DisplaySystem, settings: SettingsStore) {
        self.system = system
        self.settings = settings
    }

    public var currentGlasses: GlassesInfo? { glasses }
    public var virtualDisplayID: CGDirectDisplayID? { virtualHandle?.displayID }

    /// Every online display that could mirror the virtual one — i.e. all of
    /// them except the virtual display itself.
    public var mirrorableDisplays: [DisplayInfo] {
        guard let v = virtualHandle?.displayID else { return [] }
        return system.onlineDisplays().filter { $0.id != v }.map(namingGlasses)
    }

    /// A display in a mirror set is dropped from NSScreen, so its name decays
    /// to "Display N". The watcher captured the real one before mirroring, so
    /// prefer that.
    private func namingGlasses(_ info: DisplayInfo) -> DisplayInfo {
        guard let g = glasses, g.displayID == info.id, !g.name.isEmpty else { return info }
        return DisplayInfo(id: info.id, name: g.name, vendorID: info.vendorID,
                           productID: info.productID, serialNumber: info.serialNumber,
                           isBuiltin: info.isBuiltin)
    }

    private var desiredMirrorIDs: [CGDirectDisplayID] {
        mirrorableDisplays.filter { settings.mirrorsVirtual($0) }.map(\.id)
    }

    /// Displays currently mirroring the virtual display, for showing real
    /// state in the UI rather than just the stored intent.
    public var activeMirrorIDs: Set<CGDirectDisplayID> {
        guard let v = virtualHandle?.displayID else { return [] }
        return Set(system.onlineDisplays().map(\.id).filter { system.mirrorSource(of: $0) == v })
    }

    public func isMirroring(_ display: DisplayInfo) -> Bool { settings.mirrorsVirtual(display) }

    public func setMirroring(_ on: Bool, for display: DisplayInfo) {
        settings.setMirrorsVirtual(on, for: display)
        handle(.mirrorPreferencesChanged)
    }

    public var isAutoMirrorEnabled: Bool { settings.autoMirror }

    public func setAutoMirror(_ on: Bool) {
        settings.autoMirror = on
        if on { handle(.mirrorPreferencesChanged) }
    }

    public func handle(_ event: DisplayEvent) {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingEvents.append(event)
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        while !pendingEvents.isEmpty { process(pendingEvents.removeFirst()) }
    }

    private func process(_ event: DisplayEvent) {
        let before = state
        defer {
            if before != state || !event.isPeriodic {
                xfakeTrace("process event=\(event) state=\(before) -> \(state)")
            }
        }
        switch event {
        case .glassesAppeared(let info):
            let sessionActive = virtualHandle != nil
            if sessionActive, glasses?.displayID == info.displayID, glasses?.native == info.native {
                return // watcher rescan duplicate — nothing changed
            }
            if sessionActive { teardown(to: .idle) }
            glasses = info
            beginSession()
        case .glassesModeChanged(let info):
            teardown(to: .idle)
            glasses = info
            beginSession()
        case .glassesDisappeared(let id):
            guard glasses?.displayID == id else { return }
            teardown(to: .idle)
            glasses = nil
        case .virtualOnline(let id):
            guard case .virtualCreating = state, id == virtualHandle?.displayID else { return }
            completeSession()
        case .virtualTerminated(let id):
            guard id == virtualHandle?.displayID else { return } // stale callback from a replaced display
            virtualHandle = nil
            setState(.error("virtual display terminated by WindowServer"))
        case .reconfigured:
            repairIfNeeded()
            adoptExternalModeChangeIfNeeded()
        case .mirrorPreferencesChanged:
            applyMirrorPreferences()
        case .enabledChanged(let enabled):
            if enabled, glasses != nil, canStartSession(from: state) {
                beginSession()
            } else if !enabled {
                teardown(to: glasses != nil ? .glassesPresent : .idle)
            }
        }
    }

    // MARK: - Transitions

    private func canStartSession(from state: SessionState) -> Bool {
        switch state {
        case .idle, .glassesPresent, .error: return true
        case .virtualCreating, .mirrored: return false
        }
    }

    private func beginSession() {
        guard let g = glasses else { return }
        guard settings.isEnabled else { setState(.glassesPresent); return }

        let ladder = ModeLadder.generate(native: g.native)
        let aspect = AspectRatio(of: g.native)
        let config = VirtualDisplayConfig(
            name: "Virtual - \(g.name)",
            vendorID: g.vendorID,      // copy glasses identity so macOS persists
            productID: g.productID,    // arrangement/mode across sessions
            // Serial from vendor:product identity, not the name: while
            // mirrored, NSScreen omits the mirrored display and the name can
            // fall back to "Display N", which would change the serial across
            // mode toggles and weaken macOS's arrangement persistence.
            serialNum: xfakeStableSerial(for: "\(g.vendorID):\(g.productID)"),
            sizeInMM: CGSize(width: 600, height: 600.0 * Double(aspect.h) / Double(aspect.w)),
            modes: ladder
        )
        // Retry once: applySettings' only failure signal is a nil result.
        for _ in 0..<2 {
            if let handle = system.createVirtualDisplay(config, onTermination: { [weak self] id in
                self?.handle(.virtualTerminated(id))
            }) {
                virtualHandle = handle
                setState(.virtualCreating)
                return
            }
        }
        setState(.error("failed to create virtual display"))
    }

    private func completeSession() {
        guard let g = glasses, let v = virtualHandle else { return }
        // Auto-mirror off means the user drives the mirror set by hand from the
        // menu, so leave the topology (and the main display) untouched here.
        if settings.autoMirror {
            guard system.applyMirrorTopology(master: v.displayID, mirrors: desiredMirrorIDs) else {
                teardown(to: .error("mirror configuration failed"))
                return
            }
        }
        // No stored preference -> native, the sharpest possible mode. Without
        // this, first run stays at whatever macOS picked when creating the
        // virtual display, which defaults to the ladder's blurriest end.
        let mode = settings.preferredMode(for: AspectRatio(of: g.native)) ?? g.native
        if !system.applyMode(v.displayID, mode: mode) {
            Self.log.error("completeSession: applyMode \(mode.description, privacy: .public) failed on display \(v.displayID)")
        }
        setState(.mirrored(virtual: v.displayID, glasses: g.displayID))
    }

    private func teardown(to target: SessionState) {
        // No live virtual display -> xfake owns no WindowServer state; never
        // touch mirroring or the main display in that case.
        guard let v = virtualHandle?.displayID else { setState(target); return }
        // Always release our whole mirror set BEFORE destroying the master,
        // or WindowServer is left holding a set whose source is gone.
        for display in system.onlineDisplays() where display.id != v && system.mirrorSource(of: display.id) == v {
            _ = system.unmirror(display.id)
        }
        virtualHandle = nil // releases XFVirtualDisplay -> WindowServer removes the display
        if let builtin = system.builtinDisplayID(), !system.setMain(builtin) {
            Self.log.error("teardown: failed to restore builtin display \(builtin) as main")
        }
        setState(target)
    }

    /// Reconciles the actual mirror set against the desired one — after wake,
    /// after a hotplug, or any time macOS rearranges displays out from under
    /// us. Driven by the desired set rather than a remembered display ID, so a
    /// display that has gone away simply drops out instead of wedging repair.
    private func repairIfNeeded() {
        guard case .mirrored(let v, _) = state, settings.autoMirror else { return }
        guard system.isOnline(v) else { return }
        let desired = Set(desiredMirrorIDs)
        let actual = Set(system.onlineDisplays().map(\.id).filter { system.mirrorSource(of: $0) == v })
        guard desired != actual else { return }
        if !system.applyMirrorTopology(master: v, mirrors: Array(desired)) {
            Self.log.error("repair: failed to restore mirror topology on \(v)")
        }
    }

    /// Re-applies the topology after the user changes a mirror toggle. Runs
    /// even when auto-mirroring is off: the toggle IS the explicit instruction.
    private func applyMirrorPreferences() {
        guard case .mirrored(let v, _) = state else { return }
        if !system.applyMirrorTopology(master: v, mirrors: desiredMirrorIDs) {
            Self.log.error("mirror preferences: failed to apply topology on \(v)")
        }
    }

    /// Adopts a resolution the user picked outside xfake (e.g. in System
    /// Settings) instead of silently overriding it with a stale stored
    /// preference on the next session rebuild. If the virtual display's
    /// current mode matches a ladder entry, that becomes the new preference;
    /// otherwise the stored preference is cleared so macOS's own per-display
    /// memory (keyed by our stable vendor/product/serial) wins going forward.
    private func adoptExternalModeChangeIfNeeded() {
        guard case .mirrored(let v, _) = state, let g = glasses else { return }
        guard let current = system.currentMode(of: v) else { return }
        let aspect = AspectRatio(of: g.native)
        let ladder = ModeLadder.generate(native: g.native)
        if let match = ladder.first(where: { $0.width == current.width && $0.height == current.height }) {
            if settings.preferredMode(for: aspect) != match {
                settings.setPreferredMode(match, for: aspect)
            }
        } else {
            settings.clearPreferredMode(for: aspect)
        }
    }

    private func setState(_ new: SessionState) {
        state = new
        onStateChange?(new)
    }
}
