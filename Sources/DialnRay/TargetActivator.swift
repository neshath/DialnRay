import AppKit
import ApplicationServices
import DialnRayCore
import Foundation

enum ActivationError: LocalizedError {
    case unavailable
    case failed(AXError)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The selected control is no longer available. Scan again and retry."
        case .failed: return "The app did not accept that action. Try pointer-click mode for this control."
        }
    }
}

final class TargetActivator {
    func activate(_ discovered: DiscoveredTarget) throws {
        if let element = discovered.accessibilityElement {
            switch discovered.candidate.action {
            case .press:
                let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                if result == .success { return }
                if result != .actionUnsupported { throw ActivationError.failed(result) }
            case .focus:
                let result = AXUIElementSetAttributeValue(
                    element,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                )
                if result == .success {
                    selectAllText(in: element)
                    return
                }
            case .click:
                break
            }
        }

        let point = ScreenGeometry.cgPointFromAppKit(discovered.candidate.center)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            throw ActivationError.unavailable
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func selectAllText(in element: AXUIElement) {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &rawValue) == .success,
              let value = rawValue as? String,
              !value.isEmpty else { return }
        var range = CFRange(location: 0, length: (value as NSString).length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
    }
}
