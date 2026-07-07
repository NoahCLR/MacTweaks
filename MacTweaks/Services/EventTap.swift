import CoreGraphics
import Foundation
import os

/// Deep module owning a `CGEvent` tap's full lifecycle: creation, the run-loop
/// source on the main run loop, enable/disable, the mandatory re-enable after the
/// system disables the tap on timeout or user input, and the C callback
/// trampoline with its `Unmanaged` bridging.
///
/// Callers supply the events they care about and a handler; they never see the
/// `tapDisabledBy*` lifecycle events (EventTap re-enables the tap and swallows
/// them). This is the single home for the fragile Core Graphics ritual that the
/// three tweak controllers used to each copy.
final class EventTap {
    private let mask: CGEventMask
    private let place: CGEventTapPlacement
    private let handler: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    private let logger = Logger(subsystem: "com.noah.MacTweaks", category: "EventTap")

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// - Parameters:
    ///   - eventsOfInterest: the event types the handler wants. The tap-disabled
    ///     lifecycle events are added automatically and handled internally.
    ///   - place: where to insert the tap. Head-insert (default) runs before
    ///     other taps; tail-append lets earlier taps (e.g. a mouse remapper)
    ///     observe or rewrite the event first.
    ///   - handler: invoked for each real event; returns the (possibly modified)
    ///     event to pass on, or `nil` to swallow it.
    init(eventsOfInterest: CGEventMask,
         place: CGEventTapPlacement = .headInsertEventTap,
         handler: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) {
        self.mask = eventsOfInterest
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        self.place = place
        self.handler = handler
    }

    var isRunning: Bool { tap != nil }

    /// Creates and enables the tap if not already running. Returns whether a tap
    /// is running afterwards; a `false` return means creation failed (typically a
    /// missing permission — the caller has the context to log why).
    @discardableResult
    func enable() -> Bool {
        guard tap == nil else { return true }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: place,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapTrampoline,
            userInfo: userInfo
        ) else {
            logger.error("Could not create event tap")
            return false
        }

        tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func disable() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        return handler(type, event)
    }
}

private let eventTapTrampoline: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.receive(type: type, event: event)
}
