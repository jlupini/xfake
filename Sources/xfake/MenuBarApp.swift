import SwiftUI
import ServiceManagement
import CGVirtualDisplayBridge
import XFakeCore

@MainActor
final class AppModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var isEnabled: Bool
    @Published var launchAtLogin: Bool

    let controller: SessionController
    let watcher: GlassesWatcher
    private let settings: SettingsStore
    private let displaySystem: RealDisplaySystem

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.isEnabled = settings.isEnabled
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        let displaySystem = RealDisplaySystem()
        self.displaySystem = displaySystem
        let controller = SessionController(system: displaySystem, settings: settings)
        self.controller = controller
        self.watcher = GlassesWatcher(vendorIDs: xrealVendorIDs,
                                      ownVirtualID: { [weak controller] in controller?.virtualDisplayID })
        // SessionController invokes onStateChange synchronously from within
        // handle(_:), which asserts it's already running on the main queue
        // (see dispatchPrecondition in SessionController.handle). Both this
        // callback and the watcher's onEvent below are therefore always
        // delivered on the main thread already; MainActor.assumeIsolated
        // documents that fact instead of adding a redundant async hop that
        // would let a stale event apply after a newer one.
        controller.onStateChange = { [weak self] new in
            MainActor.assumeIsolated {
                self?.state = new
            }
        }
        watcher.onEvent = { [weak controller] event in controller?.handle(event) }
        watcher.start()
    }

    var statusText: String {
        switch state {
        case .idle: return "Glasses not connected"
        case .glassesPresent: return "Glasses connected (xfake off)"
        case .virtualCreating: return "Creating virtual display…"
        case .mirrored: return "Mirrored · \(currentModeDescription)"
        case .error(let message): return "Error: \(message)"
        }
    }

    var currentModeDescription: String {
        guard case .mirrored(let virtualID, _) = state,
              let mode = CGDisplayCopyDisplayMode(virtualID) else { return "" }
        return "\(mode.width)x\(mode.height) HiDPI"
    }

    var ladder: [ModeSpec] {
        guard let glasses = controller.currentGlasses else { return [] }
        return ModeLadder.generate(native: glasses.native)
    }

    /// The curated subset shown in the menu; the full ladder stays reachable via
    /// System Settings.
    var presets: [ModeSpec] {
        guard let glasses = controller.currentGlasses else { return [] }
        return modePresets(ladder: ladder, native: glasses.native)
    }

    /// The virtual display's current logical mode, for marking the active
    /// ladder entry. Only width/height are meaningful for comparison — CG
    /// reports refresh imprecisely (e.g. 119.99 instead of 120).
    var currentLogicalMode: ModeSpec? {
        guard case .mirrored(let virtualID, _) = state,
              let mode = CGDisplayCopyDisplayMode(virtualID) else { return nil }
        return ModeSpec(width: mode.width, height: mode.height, refresh: mode.refreshRate)
    }

    func selectMode(_ mode: ModeSpec) {
        guard case .mirrored(let virtualID, _) = state,
              let glasses = controller.currentGlasses else { return }
        if displaySystem.applyMode(virtualID, mode: mode) {
            settings.setPreferredMode(mode, for: AspectRatio(of: glasses.native))
            objectWillChange.send()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        settings.isEnabled = enabled
        controller.handle(.enabledChanged(enabled))
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = on
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func quit() {
        controller.handle(.enabledChanged(false)) // graceful teardown first
        NSApp.terminate(nil)
    }
}

struct StatusMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.statusText)
        Divider()
        Toggle("Enabled", isOn: Binding(
            get: { model.isEnabled },
            set: { model.setEnabled($0) }
        ))
        if case .mirrored = model.state {
            Menu("Resolution") {
                ForEach(model.presets, id: \.self) { mode in
                    let native = model.controller.currentGlasses?.native ?? mode
                    let current = model.currentLogicalMode
                    let isCurrent = current?.width == mode.width && current?.height == mode.height
                    Button((isCurrent ? "✓ " : "") + modeLabel(for: mode, native: native)) { model.selectMode(mode) }
                }
                Divider()
                Button("More sizes in System Settings › Displays") {}.disabled(true)
            }
        }
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))
        Button("Quit xfake") { model.quit() }
    }
}

struct XFakeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("xfake", systemImage: "eyeglasses") {
            StatusMenu(model: model)
        }
    }
}
