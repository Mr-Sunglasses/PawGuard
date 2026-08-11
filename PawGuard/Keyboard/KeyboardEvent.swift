import CoreGraphics
import Foundation

enum KeyboardEventKind: Equatable {
    case keyDown
    case keyUp
    case flagsChanged

    init?(eventType: CGEventType) {
        switch eventType {
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        case .flagsChanged: self = .flagsChanged
        default: return nil
        }
    }
}

struct KeyboardEventSample {
    let keyCode: CGKeyCode
    let timestamp: TimeInterval
    let type: KeyboardEventKind
    let isRepeat: Bool
    let modifiers: CGEventFlags

    init(
        keyCode: CGKeyCode,
        timestamp: TimeInterval,
        type: KeyboardEventKind,
        isRepeat: Bool = false,
        modifiers: CGEventFlags = []
    ) {
        self.keyCode = keyCode
        self.timestamp = timestamp
        self.type = type
        self.isRepeat = isRepeat
        self.modifiers = modifiers
    }
}
