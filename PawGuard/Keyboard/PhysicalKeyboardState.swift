import CoreGraphics
import Foundation

/// Reads which keys are physically down straight from the window server.
///
/// Inferring held keys from the event stream alone goes wrong in ways that
/// matter: a key-up lost while the tap was disabled pins a key down forever,
/// and a paw already resting on the keyboard when PawGuard launches produces no
/// events at all. This is the ground truth to reconcile against.
enum PhysicalKeyboardState {
    /// Every key code the geometry model knows about, plus modifiers.
    private static let probedKeys: [CGKeyCode] = {
        (0...127).map(CGKeyCode.init).filter {
            KeyboardGeometry.isKnownKey($0) || KeyboardGeometry.isModifier($0)
        }
    }()

    static func pressedKeys(stateID: CGEventSourceStateID = .combinedSessionState) -> Set<CGKeyCode> {
        var pressed = Set<CGKeyCode>()
        for key in probedKeys where CGEventSource.keyState(stateID, key: key) {
            pressed.insert(key)
        }
        return pressed
    }

    static func pressedNonModifierKeys(stateID: CGEventSourceStateID = .combinedSessionState) -> Set<CGKeyCode> {
        pressedKeys(stateID: stateID).filter { !KeyboardGeometry.isModifier($0) }
    }
}
