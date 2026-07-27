import AppKit
import CoreGraphics
import CGVirtualDisplayBridge
import XFakeCore

// onlineDisplayIDs() comes from XFakeCore (RealDisplaySystem.swift).

func displayName(_ id: CGDirectDisplayID) -> String {
    for screen in NSScreen.screens {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           num == id {
            return screen.localizedName
        }
    }
    return "Display \(id)"
}

func runDoctor() -> Int32 {
    print("xfake doctor")
    print("  CGVirtualDisplay private API: \(XFVirtualDisplay.apiAvailable() ? "AVAILABLE" : "MISSING")")

    let betterDisplayRunning = !NSRunningApplication
        .runningApplications(withBundleIdentifier: "pro.betterdisplay.BetterDisplay").isEmpty
    print("  BetterDisplay running: \(betterDisplayRunning ? "YES — quit it before using xfake!" : "no")")

    let online = onlineDisplayIDs()
    let vendorMatches = online.filter { xrealVendorIDs.contains(CGDisplayVendorNumber($0)) }
    if vendorMatches.count > 1 {
        print("  note: multiple vendor matches — one may be a virtual display created by xfake/BetterDisplay")
    }

    for id in online {
        let vendor = CGDisplayVendorNumber(id)
        let isGlasses = xrealVendorIDs.contains(vendor)
        print("\n  Display \(id): \(displayName(id))\(isGlasses ? "  <-- GLASSES" : "")")
        print("    vendor=\(vendor) model=\(CGDisplayModelNumber(id)) serial=\(CGDisplaySerialNumber(id))")
        print("    main=\(CGDisplayIsMain(id) == 1) builtin=\(CGDisplayIsBuiltin(id) == 1) mirrorsDisplay=\(CGDisplayMirrorsDisplay(id))")
        if let mode = CGDisplayCopyDisplayMode(id) {
            print("    current: \(mode.width)x\(mode.height) (px \(mode.pixelWidth)x\(mode.pixelHeight)) @\(mode.refreshRate)Hz")
        }
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        if let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] {
            print("    modeCount=\(modes.count)")
            let oneX = modes.filter { $0.pixelWidth == $0.width }
                .sorted { ($0.pixelWidth, $0.pixelHeight, $0.refreshRate) > ($1.pixelWidth, $1.pixelHeight, $1.refreshRate) }
            for m in oneX.prefix(5) {
                print("      1x: \(m.width)x\(m.height) @\(m.refreshRate)Hz")
            }
        }
        if isGlasses, let mode = CGDisplayCopyDisplayMode(id) {
            let native = ModeSpec(width: mode.pixelWidth, height: mode.pixelHeight, refresh: mode.refreshRate)
            print("    aspect: \(AspectRatio(of: native))")
        }
        // A vendor-matching display that's currently mirroring another
        // display is the physical glasses (the virtual display is the
        // mirror master). Its own mode list still yields the correct panel
        // native even while mirrored.
        if isGlasses, CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay,
           let allModes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode],
           let current = CGDisplayCopyDisplayMode(id) {
            let raw = allModes.map {
                RawMode(width: $0.width, height: $0.height, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, refresh: $0.refreshRate)
            }
            if let panelNative = NativeMode.select(from: raw) {
                let logical = ModeSpec(width: current.width, height: current.height, refresh: current.refreshRate)
                let report = SharpnessReport(panelNative: panelNative, currentLogical: logical)
                print("    Sharpness: \(report.summary)")
            }
        }
    }
    return 0
}

func findGlasses() -> (id: CGDirectDisplayID, native: ModeSpec, name: String)? {
    for id in onlineDisplayIDs() where xrealVendorIDs.contains(CGDisplayVendorNumber(id)) {
        guard let mode = CGDisplayCopyDisplayMode(id) else { continue }
        // When unmanaged, the glasses sit at their native 1x mode.
        let native = ModeSpec(width: mode.pixelWidth, height: mode.pixelHeight, refresh: mode.refreshRate)
        return (id, native, displayName(id))
    }
    return nil
}

func runUp() -> Int32 {
    guard XFVirtualDisplay.apiAvailable() else { fputs("private API unavailable\n", stderr); return 1 }
    guard findGlasses() != nil else { fputs("no XREAL glasses found\n", stderr); return 1 }
    if !SettingsStore().isEnabled {
        fputs("xfake is disabled (Enabled toggle off); enable it or the session will idle at glassesPresent\n", stderr)
    }
    return runHeadless() // identical: session starts immediately since glasses are present
}

/// Recovers from a leftover mirror topology (e.g. a prior xfake process that
/// died without tearing down, or manual fiddling in System Settings) without
/// needing to know which display was the mirror master. Takes the
/// single-instance lock so it can't fight a live session.
func runReset() -> Int32 {
    guard acquireSingleInstanceLock() else {
        fputs("another xfake instance is already running — quit it before resetting\n", stderr)
        return 1
    }
    let system = RealDisplaySystem()
    guard let builtin = system.builtinDisplayID() else {
        fputs("xfake reset: no builtin display found\n", stderr)
        return 1
    }
    let online = onlineDisplayIDs()
    print("xfake reset: un-mirroring \(online.count) display(s): \(online)")
    print("xfake reset: setting builtin display \(builtin) (\(displayName(builtin))) as main")
    guard system.resetTopology(mainDisplay: builtin) else {
        fputs("xfake reset: failed to reset display topology\n", stderr)
        return 1
    }
    print("xfake reset: done")
    return 0
}

func makeSession() -> (SessionController, GlassesWatcher) {
    let controller = SessionController(system: RealDisplaySystem(), settings: SettingsStore())
    let watcher = GlassesWatcher(vendorIDs: xrealVendorIDs,
                                 ownVirtualID: { [weak controller] in controller?.virtualDisplayID })
    watcher.onEvent = { [weak controller] event in controller?.handle(event) }
    return (controller, watcher)
}

func runHeadless() -> Int32 {
    guard acquireSingleInstanceLock() else {
        fputs("another xfake instance is already running\n", stderr)
        return 1
    }
    guard XFVirtualDisplay.apiAvailable() else { fputs("private API unavailable\n", stderr); return 1 }
    let (controller, watcher) = makeSession()
    controller.onStateChange = { print("state: \($0)") }

    signal(SIGINT, SIG_IGN)
    let sigSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigSrc.setEventHandler {
        controller.handle(.enabledChanged(false)) // graceful teardown
        exit(0)
    }
    sigSrc.resume()
    // Print the banner before starting the watcher so the initial state
    // transitions (which watcher.start() can fire synchronously) appear
    // after it, not buried above it.
    print("xfake run: watching for glasses (Ctrl-C to stop)")
    watcher.start()
    // In release builds ARC may release these locals before RunLoop.run()
    // returns (it never does) — keep the session and signal source alive.
    withExtendedLifetime((controller, watcher, sigSrc)) {
        RunLoop.main.run()
    }
    return 0
}

/// Blocking modal alert for failures in the menu bar app path — stderr is
/// invisible when launched from Finder (LSUIElement, no terminal).
func showFatalAlert(message: String, informative: String) {
    _ = NSApplication.shared // ensure the app connection exists for the panel
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = message
    alert.informativeText = informative
    alert.runModal()
}

func runMenuBarApp() {
    guard acquireSingleInstanceLock() else {
        fputs("another xfake instance is already running\n", stderr)
        showFatalAlert(message: "xfake is already running",
                       informative: "Another xfake instance (menu bar app or CLI) already manages the glasses. Quit it before starting a new one.")
        exit(1)
    }
    guard XFVirtualDisplay.apiAvailable() else {
        fputs("xfake: CGVirtualDisplay private API unavailable on this macOS — cannot run\n", stderr)
        showFatalAlert(message: "xfake cannot run on this macOS",
                       informative: "The private CGVirtualDisplay API this app depends on is unavailable in this macOS version.")
        exit(1)
    }
    XFakeApp.main()
}
