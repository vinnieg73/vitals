import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    /// False when another app already has this shortcut (eventHotKeyExistsErr), so pressing it won't reach Vitals.
    private(set) var registered = false

    /// ⌃⌥⌘V by default (⌥⌘V is Finder's "Move Item Here").
    init(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | optionKey | controlKey), action: @escaping () -> Void) {
        self.action = action
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

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
