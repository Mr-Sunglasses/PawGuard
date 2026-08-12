import CoreGraphics
import Foundation

final class KeyboardEventMonitor {
    private let handler: (KeyboardEventSample) -> Bool
    private let interruptionHandler: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private(set) var isRunning = false
    private(set) var lastStartError: String?

    init(
        handler: @escaping (KeyboardEventSample) -> Bool,
        interruptionHandler: @escaping () -> Void = {}
    ) {
        self.handler = handler
        self.interruptionHandler = interruptionHandler
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let eventMask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << CGEventMask($1.rawValue))
        }
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: Self.eventTapCallback,
                userInfo: unmanagedSelf
            )
        else {
            lastStartError = "PawGuard could not create its keyboard event tap."
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            lastStartError = "PawGuard could not attach its keyboard monitor."
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        lastStartError = nil
        return true
    }

    func stop() {
        guard let source = runLoopSource, let eventTap else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: false)
        self.eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    func reenable() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            interruptionHandler()
            reenable()
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            guard let kind = KeyboardEventKind(eventType: type) else {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let timestamp = Double(event.timestamp) / 1_000_000_000
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let sample = KeyboardEventSample(
                keyCode: keyCode,
                timestamp: timestamp,
                type: kind,
                isRepeat: isRepeat,
                modifiers: event.flags
            )
            return handler(sample) ? Unmanaged.passUnretained(event) : nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
        return monitor.handle(type: type, event: event)
    }

    deinit {
        stop()
    }
}
