import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let keyCode: UInt32
    private let modifiers: UInt32
    /// False when another app already has this shortcut (eventHotKeyExistsErr), so pressing it won't reach Vitals.
    private(set) var registered = false

    /// It's one of macOS's own shortcuts that's turned on (System Settings → Keyboard → Keyboard Shortcuts), so
    /// macOS gets it first even though registering worked. Looked up each time (those can change while Vitals runs).
    /// Another app's plain (non-exclusive) registration or an event tap still can't be seen from here.
    var takenBySystem: Bool { Self.isSystemShortcut(keyCode: keyCode, modifiers: modifiers) }

    static func isSystemShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        systemShortcuts().contains { $0.code == keyCode && $0.mods == modifiers }
    }

    /// ⌃⌥⌘V by default (⌥⌘V is Finder's "Move Item Here").
    init(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | optionKey | controlKey), action: @escaping () -> Void) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            guard let ctx else { return noErr }
            let hk = Unmanaged<Hotkey>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { hk.action() }
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x5654_4C53), id: 1) // 'VTLS'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        registered = status == noErr
        if !registered { NSLog("Vitals: shortcut not registered (OSStatus \(status)); another app probably has it") }
    }

    /// macOS's own shortcuts that are turned on (key code and Carbon modifiers), from CopySymbolicHotKeys.
    static func systemShortcuts() -> [(code: UInt32, mods: UInt32)] {
        var ref: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&ref) == noErr, let cf = ref?.takeRetainedValue(),
              let list = (cf as NSArray) as? [[String: Any]] else { return [] }
        return list.compactMap { e in
            guard (e["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                  let code = (e["kHISymbolicHotKeyCode"] as? NSNumber)?.uint32Value,
                  let mods = (e["kHISymbolicHotKeyModifiers"] as? NSNumber)?.uint32Value else { return nil }
            return (code, mods)
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
