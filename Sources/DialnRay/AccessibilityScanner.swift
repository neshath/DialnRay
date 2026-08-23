import AppKit
import ApplicationServices
import DialnRayCore
import Foundation

final class DiscoveredTarget {
    let candidate: TargetCandidate
    let accessibilityElement: AXUIElement?

    init(candidate: TargetCandidate, accessibilityElement: AXUIElement? = nil) {
        self.candidate = candidate
        self.accessibilityElement = accessibilityElement
    }
}

struct AccessibilityScanResult {
    var app: AppContext
    var targets: [DiscoveredTarget]
    var staticTextTargets: [DiscoveredTarget]
}

final class AccessibilityScanner {
    private let actionableRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXComboBoxRole as String,
        "AXLink",
        kAXMenuButtonRole as String,
        kAXMenuItemRole as String,
        kAXPopUpButtonRole as String,
        kAXRadioButtonRole as String,
        kAXSliderRole as String,
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXColorWell",
        "AXDisclosureTriangle",
        "AXIncrementor",
    ]

    private let editableRoles: Set<String> = [
        kAXComboBoxRole as String,
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
    ]

    func scan(frontmostApp app: NSRunningApplication, cursor: CGPoint) -> AccessibilityScanResult {
        let bundleIdentifier = app.bundleIdentifier ?? "unknown.\(app.processIdentifier)"
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindow = elementAttribute(applicationElement, kAXFocusedWindowAttribute as String)
        let windowTitle = stringAttribute(focusedWindow, kAXTitleAttribute as String)
        let rawWindowFrame = frame(of: focusedWindow)
        let windowFrame = rawWindowFrame.map(ScreenGeometry.appKitRectFromAX)
        let context = AppContext(
            bundleIdentifier: bundleIdentifier,
            displayName: app.localizedName ?? bundleIdentifier,
            processIdentifier: app.processIdentifier,
            windowTitle: windowTitle,
            windowFrame: windowFrame
        )

        guard let root = focusedWindow ?? Optional(applicationElement) else {
            return AccessibilityScanResult(app: context, targets: [], staticTextTargets: [])
        }

        var queue: [AXUIElement] = [root]
        if let focusedWindow {
            let priorityAttributes = [
                "AXCloseButton",
                "AXMinimizeButton",
                "AXZoomButton",
                "AXFullScreenButton",
                "AXToolbarButton",
            ]
            queue.append(contentsOf: priorityAttributes.compactMap {
                elementAttribute(focusedWindow, $0)
            })
        }
        var queueIndex = 0
        var actionable: [DiscoveredTarget] = []
        var staticText: [DiscoveredTarget] = []
        var visited = 0
        // Web pages expose much deeper accessibility trees than native windows.
        // Keep the scan bounded, but allow enough time and nodes to reach the
        // individual AXLink elements in article bodies such as Wikipedia.
        let deadline = CFAbsoluteTimeGetCurrent() + 0.36

        while queueIndex < queue.count, visited < 4_000, CFAbsoluteTimeGetCurrent() < deadline {
            let element = queue[queueIndex]
            queueIndex += 1
            visited += 1

            let role = stringAttribute(element, kAXRoleAttribute as String) ?? "unknown"
            if let rawFrame = frame(of: element) {
                let appKitFrame = ScreenGeometry.appKitRectFromAX(rawFrame)
                let nearCursor = hypot(appKitFrame.midX - cursor.x, appKitFrame.midY - cursor.y) <= 1_200
                let visible = windowFrame?.intersects(appKitFrame) ?? true
                if nearCursor, visible, appKitFrame.width >= 4, appKitFrame.height >= 4 {
                    let label = bestLabel(for: element, role: role)
                    let actions = actionNames(for: element)
                    let canPress = actions.contains(kAXPressAction as String)
                    let isLink = role == "AXLink"
                    let isEditable = editableRoles.contains(role)
                    let enabled = boolAttribute(element, kAXEnabledAttribute as String) ?? true
                    if enabled, actionableRoles.contains(role) {
                        let action: TargetAction = isEditable ? .focus : (canPress ? .press : .click)
                        let confidence = (isEditable || isLink) ? 1.0 : (canPress ? 0.98 : 0.84)
                        let candidate = TargetCandidate(
                            label: label,
                            role: role.replacingOccurrences(of: "AX", with: ""),
                            frame: appKitFrame,
                            source: .accessibility,
                            confidence: confidence,
                            action: action
                        )
                        actionable.append(DiscoveredTarget(candidate: candidate, accessibilityElement: element))
                    } else if role == kAXStaticTextRole as String, !label.isEmpty, appKitFrame.width <= 360, appKitFrame.height <= 72 {
                        let expanded = appKitFrame.insetBy(dx: -8, dy: -7)
                        let candidate = TargetCandidate(
                            label: label,
                            role: "Predicted control",
                            frame: expanded,
                            source: .layout,
                            confidence: 0.56,
                            action: .click
                        )
                        staticText.append(DiscoveredTarget(candidate: candidate))
                    }
                }
            }

            queue.append(contentsOf: childElements(of: element))
        }

        return AccessibilityScanResult(
            app: context,
            targets: deduplicate(actionable),
            staticTextTargets: deduplicate(staticText)
        )
    }

    private func bestLabel(for element: AXUIElement, role: String) -> String {
        let candidates = [
            stringAttribute(element, kAXTitleAttribute as String),
            stringAttribute(element, kAXDescriptionAttribute as String),
            stringAttribute(element, kAXHelpAttribute as String),
            stringAttribute(element, kAXValueAttribute as String),
            stringAttribute(element, kAXIdentifierAttribute as String),
        ]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? role.replacingOccurrences(of: "AX", with: "")
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        if let visible = arrayAttribute(element, kAXVisibleChildrenAttribute as String), !visible.isEmpty {
            return visible
        }
        return arrayAttribute(element, kAXChildrenAttribute as String) ?? []
    }

    private func actionNames(for element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as! AXUIElement?
    }

    private func stringAttribute(_ element: AXUIElement?, _ attribute: String) -> String? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func arrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func frame(of element: AXUIElement?) -> CGRect? {
        guard let element else { return nil }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAX = positionValue as! AXValue?,
              let sizeAX = sizeValue as! AXValue? else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func deduplicate(_ targets: [DiscoveredTarget]) -> [DiscoveredTarget] {
        var accepted: [DiscoveredTarget] = []
        for target in targets.sorted(by: { $0.candidate.confidence > $1.candidate.confidence }) {
            let duplicate = accepted.contains { existing in
                let intersection = existing.candidate.frame.intersection(target.candidate.frame)
                guard !intersection.isNull else { return false }
                let smallerArea = min(existing.candidate.frame.area, target.candidate.frame.area)
                return smallerArea > 0 && (intersection.area / smallerArea) > 0.76
            }
            if !duplicate { accepted.append(target) }
        }
        return accepted
    }
}

enum ScreenGeometry {
    static func appKitRectFromAX(_ rect: CGRect) -> CGRect {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

private extension CGRect {
    var area: CGFloat { max(width, 0) * max(height, 0) }
}
