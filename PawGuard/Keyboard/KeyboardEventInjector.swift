import CoreGraphics
import Foundation

/// Marks events PawGuard posts itself so its own tap ignores them instead of
/// scoring them as new cat activity.
enum InjectedEvent {
    static let marker: Int64 = 0x5061_7747  // "PawG"

    static func isInjected(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }
}

protocol KeyboardEventInjecting: AnyObject {
    /// Tells the frontmost app that a key it saw go down has come back up.
    func releaseKeys(_ keyCodes: [CGKeyCode])
    /// Delivers events that were withheld during a grace window and turned out
    /// to be human input.
    func replay(_ events: [KeyboardEventSample])
    /// Removes characters the cat managed to type before protection engaged.
    func deleteBackward(count: Int)
}

final class KeyboardEventInjector: KeyboardEventInjecting {
    private let source = CGEventSource(stateID: .privateState)

    func releaseKeys(_ keyCodes: [CGKeyCode]) {
        for keyCode in keyCodes {
            post(keyCode: keyCode, keyDown: false, flags: [])
        }
    }

    func replay(_ events: [KeyboardEventSample]) {
        for event in events {
            switch event.type {
            case .keyDown:
                post(keyCode: event.keyCode, keyDown: true, flags: event.modifiers)
            case .keyUp:
                post(keyCode: event.keyCode, keyDown: false, flags: event.modifiers)
            case .flagsChanged:
                // Flag state is carried on the replayed key events themselves;
                // replaying a bare flags change would desynchronise modifiers.
                continue
            }
        }
    }

    func deleteBackward(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<min(count, 512) {
            post(keyCode: 51, keyDown: true, flags: [])
            post(keyCode: 51, keyDown: false, flags: [])
        }
    }

    private func post(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: InjectedEvent.marker)
        event.post(tap: .cghidEventTap)
    }
}
