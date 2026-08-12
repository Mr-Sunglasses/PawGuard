import CoreGraphics
import Foundation
import os

/// Owns the Core Graphics event tap.
///
/// The tap runs on its own thread with its own run loop. On the main run loop
/// every keystroke on the system would be dispatched behind SwiftUI rendering,
/// so a slow frame delays input machine-wide and a slow enough one makes macOS
/// disable the tap outright.
final class KeyboardEventMonitor {
    private let handler: (KeyboardEventSample) -> Bool
    private let interruptionHandler: () -> Void
    private let logger = Logger(subsystem: "com.pawguard.app", category: "keyboard")

    private let stateLock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?
    private var running = false
    private var startError: String?

    private(set) var timeoutCount = 0

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    var lastStartError: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startError
    }

    init(
        handler: @escaping (KeyboardEventSample) -> Bool,
        interruptionHandler: @escaping () -> Void = {}
    ) {
        self.handler = handler
        self.interruptionHandler = interruptionHandler
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }

        let ready = DispatchSemaphore(value: 0)
        var succeeded = false

        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }
            succeeded = self.installTap()
            self.stateLock.lock()
            self.tapRunLoop = CFRunLoopGetCurrent()
            self.running = succeeded
            self.stateLock.unlock()
            ready.signal()
            guard succeeded else { return }
            // Keeps the run loop alive even with no sources left attached.
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
        }
        thread.name = "com.pawguard.keyboard-tap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()

        if !succeeded { self.thread = nil }
        return succeeded
    }

    func stop() {
        stateLock.lock()
        let tap = eventTap
        let source = runLoopSource
        let loop = tapRunLoop
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        running = false
        stateLock.unlock()

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source, let loop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFRunLoopWakeUp(loop)
        }
        thread?.cancel()
        thread = nil
    }

    /// Re-enables a tap macOS switched off. If the port itself is gone, builds
    /// a new one rather than leaving the app silently unprotected.
    func recover() {
        stateLock.lock()
        let tap = eventTap
        stateLock.unlock()

        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            return
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return }
        }
        logger.warning("Keyboard tap could not be re-enabled; rebuilding it.")
        stop()
        _ = start()
    }

    private func installTap() -> Bool {
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
            stateLock.lock()
            startError = "PawGuard could not create its keyboard event tap."
            stateLock.unlock()
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            stateLock.lock()
            startError = "PawGuard could not attach its keyboard monitor."
            stateLock.unlock()
            return false
        }

        stateLock.lock()
        eventTap = tap
        runLoopSource = source
        startError = nil
        stateLock.unlock()

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            timeoutCount += 1
            logger.warning("Keyboard tap disabled by timeout (\(self.timeoutCount, privacy: .public)); re-enabling.")
            interruptionHandler()
            recover()
            return Unmanaged.passUnretained(event)
        case .tapDisabledByUserInput:
            interruptionHandler()
            recover()
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            // Events PawGuard posted itself (replayed input, synthetic key-ups,
            // undo deletes) must pass straight through.
            guard !InjectedEvent.isInjected(event) else {
                return Unmanaged.passUnretained(event)
            }
            guard let kind = KeyboardEventKind(eventType: type) else {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let timestamp = MonotonicClock.eventSeconds(event.timestamp)
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
