import Carbon.HIToolbox
import Foundation

// Global C-compatible callback — Carbon requires a plain function, not a closure
private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    theEvent: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    NotificationCenter.default.post(name: .fridayToggle, object: nil)
    return noErr
}

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var observer: NSObjectProtocol?

    init(action: @escaping @Sendable () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: .fridayToggle,
            object: nil,
            queue: .main
        ) { _ in
            action()
        }
        register()
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
    }

    private func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCC("FRdY"), id: 1)

        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

private func fourCC(_ string: String) -> OSType {
    string.utf8.prefix(4).reduce(0) { result, byte in
        result << 8 | OSType(byte)
    }
}

extension Notification.Name {
    static let fridayToggle = Notification.Name("com.friday.toggle")
}
