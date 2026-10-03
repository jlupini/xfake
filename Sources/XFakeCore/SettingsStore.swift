import Foundation

public final class SettingsStore {
    private enum Keys {
        static let enabled = "xfake.enabled"
        static let autoMirror = "xfake.autoMirror"
        static func preferredMode(for aspect: AspectRatio) -> String {
            "preferred.\(aspect.w)x\(aspect.h)"
        }
        static func mirrors(_ display: DisplayInfo) -> String {
            "mirror.\(display.persistentKey)"
        }
    }

    private let defaults: UserDefaults

    /// Defaults to the explicit "com.jlupini.xfake" suite so the bare CLI
    /// binary (nil bundle ID, where .standard is a different domain) and the
    /// bundled app share preferences. Inside the bundled app the suite name
    /// equals the main bundle ID, which makes UserDefaults(suiteName:) return
    /// nil — and the .standard fallback resolves to that same domain there.
    public init(defaults: UserDefaults = UserDefaults(suiteName: "com.jlupini.xfake") ?? .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Keys.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    /// Whether a session automatically puts the configured displays into the
    /// virtual display's mirror set. Off leaves the topology untouched on
    /// connect; the per-display toggles still apply on demand.
    public var autoMirror: Bool {
        get { defaults.object(forKey: Keys.autoMirror) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoMirror) }
    }

    /// Whether this display should mirror the virtual display, falling back to
    /// the per-display default when the user has never said.
    public func mirrorsVirtual(_ display: DisplayInfo) -> Bool {
        defaults.object(forKey: Keys.mirrors(display)) as? Bool ?? display.mirrorsByDefault
    }

    public func setMirrorsVirtual(_ on: Bool, for display: DisplayInfo) {
        defaults.set(on, forKey: Keys.mirrors(display))
    }

    public func preferredMode(for aspect: AspectRatio) -> ModeSpec? {
        guard let data = defaults.data(forKey: Keys.preferredMode(for: aspect)) else { return nil }
        return try? JSONDecoder().decode(ModeSpec.self, from: data)
    }

    public func setPreferredMode(_ mode: ModeSpec, for aspect: AspectRatio) {
        guard let data = try? JSONEncoder().encode(mode) else { return }
        defaults.set(data, forKey: Keys.preferredMode(for: aspect))
    }

    /// Forgets the stored preference so macOS's own per-display mode memory
    /// (keyed by our stable vendor/product/serial) takes over instead.
    public func clearPreferredMode(for aspect: AspectRatio) {
        defaults.removeObject(forKey: Keys.preferredMode(for: aspect))
    }
}
