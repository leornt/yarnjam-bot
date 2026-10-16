import ApplicationServices
import CoreGraphics
import Foundation

final class HotkeyMonitor {
    var onKey: ((Int) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                monitor.receive(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func receive(_ event: CGEvent) {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let key: Int?
        switch code {
        case 18, 83: key = 1
        default: key = nil
        }
        guard let key else { return }
        let handler = onKey
        DispatchQueue.main.async {
            handler?(key)
        }
    }
}

func accessibilityIsTrusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func movePointer(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    let event = CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    )
    event?.post(tap: .cghidEventTap)
}

func clickPointer(at point: CGPoint) {
    movePointer(to: point)
    func post(_ type: CGEventType) {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }
    post(.leftMouseDown)
    post(.leftMouseUp)
}
