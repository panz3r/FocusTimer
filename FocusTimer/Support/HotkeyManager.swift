import Carbon.HIToolbox
import Combine
import Foundation

/// Global hotkey registration + the hotkey settings state (labels and
/// key codes, persisted through didSet). Phase 4: the hotkey settings
/// moved here from the former TimerViewModel — the Shortcuts pane binds
/// this manager directly.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?
    var onSkip: (() -> Void)?

    @Published var toggleHotkeyLabel: String
    @Published var skipHotkeyLabel: String
    /// Master switch for global hotkey registration.
    @Published var hotkeysEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotkeysEnabled, forKey: UserDefaultsKeys.hotkeysEnabled)
            if hotkeysEnabled { register() } else { unregister() }
        }
    }

    private var eventHandlerRef: EventHandlerRef?
    private var toggleHotKeyRef: EventHotKeyRef?
    private var skipHotKeyRef: EventHotKeyRef?

    private static let signature: OSType = {
        var r: OSType = 0
        for c in "FTMR".utf8 { r = (r << 8) | OSType(c) }
        return r
    }()

    private init() {
        let ud = UserDefaults.standard
        toggleHotkeyLabel = ud.string(forKey: UserDefaultsKeys.toggleHotkeyLabel) ?? "⌃⌥Space"
        skipHotkeyLabel   = ud.string(forKey: UserDefaultsKeys.skipHotkeyLabel)   ?? "⌃⌥S"
        hotkeysEnabled    = ud.object(forKey: UserDefaultsKeys.hotkeysEnabled) as? Bool ?? true
    }

    /// Replaces the Start/Pause hotkey. Refuses a collision with the Skip
    /// hotkey (the registration is left untouched in that case).
    func updateToggleHotkey(code: Int, mods: Int, label: String) {
        let ud = UserDefaults.standard
        let skipCode = ud.object(forKey: UserDefaultsKeys.skipHotkeyCode) as? Int ?? 1
        let skipMods = ud.object(forKey: UserDefaultsKeys.skipHotkeyMods) as? Int ?? 6144
        guard code != skipCode || mods != skipMods else {
            if ud.object(forKey: UserDefaultsKeys.hotkeysEnabled) as? Bool ?? true { register() }
            return
        }
        ud.set(code, forKey: UserDefaultsKeys.toggleHotkeyCode)
        ud.set(mods, forKey: UserDefaultsKeys.toggleHotkeyMods)
        ud.set(label, forKey: UserDefaultsKeys.toggleHotkeyLabel)
        toggleHotkeyLabel = label
        register()
    }

    /// Replaces the Skip hotkey. Refuses a collision with the Start/Pause
    /// hotkey (the registration is left untouched in that case).
    func updateSkipHotkey(code: Int, mods: Int, label: String) {
        let ud = UserDefaults.standard
        let toggleCode = ud.object(forKey: UserDefaultsKeys.toggleHotkeyCode) as? Int ?? 49
        let toggleMods = ud.object(forKey: UserDefaultsKeys.toggleHotkeyMods) as? Int ?? 6144
        guard code != toggleCode || mods != toggleMods else {
            if ud.object(forKey: UserDefaultsKeys.hotkeysEnabled) as? Bool ?? true { register() }
            return
        }
        ud.set(code, forKey: UserDefaultsKeys.skipHotkeyCode)
        ud.set(mods, forKey: UserDefaultsKeys.skipHotkeyMods)
        ud.set(label, forKey: UserDefaultsKeys.skipHotkeyLabel)
        skipHotkeyLabel = label
        register()
    }

    func register() {
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyHandler, 1, &spec, ptr, &eventHandlerRef)

        let ud = UserDefaults.standard
        let toggleCode = UInt32(ud.object(forKey: UserDefaultsKeys.toggleHotkeyCode) as? Int ?? Int(kVK_Space))
        let toggleMods = UInt32(ud.object(forKey: UserDefaultsKeys.toggleHotkeyMods) as? Int ?? Int(controlKey | optionKey))
        let skipCode   = UInt32(ud.object(forKey: UserDefaultsKeys.skipHotkeyCode)   as? Int ?? Int(kVK_ANSI_S))
        let skipMods   = UInt32(ud.object(forKey: UserDefaultsKeys.skipHotkeyMods)   as? Int ?? Int(controlKey | optionKey))

        let id1 = EventHotKeyID(signature: HotkeyManager.signature, id: 1)
        RegisterEventHotKey(toggleCode, toggleMods, id1, GetApplicationEventTarget(), 0, &toggleHotKeyRef)

        let id2 = EventHotKeyID(signature: HotkeyManager.signature, id: 2)
        RegisterEventHotKey(skipCode, skipMods, id2, GetApplicationEventTarget(), 0, &skipHotKeyRef)
    }

    func unregister() {
        if let ref = toggleHotKeyRef { UnregisterEventHotKey(ref); toggleHotKeyRef = nil }
        if let ref = skipHotKeyRef   { UnregisterEventHotKey(ref); skipHotKeyRef   = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref);    eventHandlerRef  = nil }
    }
}

private func carbonHotKeyHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        switch hotKeyID.id {
        case 1: manager.onToggle?()
        case 2: manager.onSkip?()
        default: break
        }
    }
    return noErr
}
