import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class InputMonitor {
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onPointer: ((CGPoint) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalFallback: Any?
    private var localFallback: Any?
    private let stateLock = NSLock()
    private var _overlayActive = false
    private var _textEntryActive = false

    var overlayActive: Bool {
        get { stateLock.withLock { _overlayActive } }
        set { stateLock.withLock { _overlayActive = newValue } }
    }

    var textEntryActive: Bool {
        get { stateLock.withLock { _textEntryActive } }
        set { stateLock.withLock { _textEntryActive = newValue } }
    }

    func start() {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: pointer
        )
        if let eventTap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            installFallbackMonitors()
        }
    }

    func stop() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let globalFallback { NSEvent.removeMonitor(globalFallback) }
        if let localFallback { NSEvent.removeMonitor(localFallback) }
        eventTap = nil
        runLoopSource = nil
        globalFallback = nil
        localFallback = nil
    }

    func refreshAfterPermissionChange() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        stop()
        start()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .mouseMoved || type == .leftMouseDragged {
            let point = ScreenGeometry.appKitPointFromCG(event.location)
            DispatchQueue.main.async { [weak self] in self?.onPointer?(point) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if keyCode == 49, flags.contains(.maskAlternate), !flags.contains(.maskCommand), !flags.contains(.maskControl) {
            DispatchQueue.main.async { [weak self] in self?.onToggle?() }
            return nil
        }
        if keyCode == 53, overlayActive {
            DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            return nil
        }
        if (keyCode == 36 || keyCode == 76), overlayActive {
            if textEntryActive { return Unmanaged.passUnretained(event) }
            DispatchQueue.main.async { [weak self] in self?.onConfirm?() }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func installFallbackMonitors() {
        let keyHandler: (NSEvent) -> Bool = { [weak self] event in
            guard let self else { return false }
            if event.keyCode == 49, event.modifierFlags.contains(.option) {
                self.onToggle?()
                return true
            }
            if event.keyCode == 53, self.overlayActive {
                self.onCancel?()
                return true
            }
            if (event.keyCode == 36 || event.keyCode == 76), self.overlayActive {
                if self.textEntryActive { return false }
                self.onConfirm?()
                return true
            }
            return false
        }
        globalFallback = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDragged]) { [weak self] event in
            if event.type == .keyDown { _ = keyHandler(event) }
            else { self?.onPointer?(NSEvent.mouseLocation) }
        }
        localFallback = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            keyHandler(event) ? nil : event
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

extension ScreenGeometry {
    static func appKitPointFromCG(_ point: CGPoint) -> CGPoint {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: desktopTop - point.y)
    }

    static func cgPointFromAppKit(_ point: CGPoint) -> CGPoint {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: desktopTop - point.y)
    }
}
