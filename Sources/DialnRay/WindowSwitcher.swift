import AppKit
import ApplicationServices
import Foundation

struct OpenAppSummary: Identifiable, Equatable {
    let id: UUID
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let appName: String
    let windowCount: Int
    let isFrontmost: Bool
}

final class OpenAppTarget {
    let summary: OpenAppSummary
    let application: NSRunningApplication
    let windows: [AXUIElement]

    init(summary: OpenAppSummary, application: NSRunningApplication, windows: [AXUIElement]) {
        self.summary = summary
        self.application = application
        self.windows = windows
    }
}

@MainActor
final class WindowSwitcher {
    func openApplications(excludingBundleIdentifier excludedBundleIdentifier: String?) -> [OpenAppTarget] {
        let zOrderedPIDs = visibleWindowProcessOrder()
        let zOrder = Dictionary(uniqueKeysWithValues: zOrderedPIDs.enumerated().map { ($1, $0) })

        return NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular
                    && !application.isTerminated
                    && application.bundleIdentifier != excludedBundleIdentifier
            }
            .compactMap { application -> OpenAppTarget? in
                let appElement = AXUIElementCreateApplication(application.processIdentifier)
                let windows = windowElements(of: appElement)
                guard !windows.isEmpty else { return nil }
                let summary = OpenAppSummary(
                    id: UUID(),
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier ?? "pid.\(application.processIdentifier)",
                    appName: application.localizedName ?? "Application",
                    windowCount: windows.count,
                    isFrontmost: application.isActive
                )
                return OpenAppTarget(summary: summary, application: application, windows: windows)
            }
            .sorted { lhs, rhs in
                let lhsOrder = zOrder[lhs.application.processIdentifier] ?? Int.max
                let rhsOrder = zOrder[rhs.application.processIdentifier] ?? Int.max
                if lhsOrder == rhsOrder {
                    return lhs.summary.appName.localizedCaseInsensitiveCompare(rhs.summary.appName) == .orderedAscending
                }
                return lhsOrder < rhsOrder
            }
    }

    func activate(_ target: OpenAppTarget) {
        for window in target.windows {
            setBoolean(false, attribute: kAXMinimizedAttribute as String, on: window)
        }
        _ = target.application.activate(options: [.activateAllWindows])
        if let window = target.windows.first {
            setBoolean(true, attribute: kAXMainAttribute as String, on: window)
            setBoolean(true, attribute: kAXFocusedAttribute as String, on: window)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    private func visibleWindowProcessOrder() -> [pid_t] {
        guard let rows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var seen = Set<pid_t>()
        var ordered: [pid_t] = []
        for row in rows {
            guard (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let owner = row[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let processIdentifier = pid_t(owner.int32Value)
            if seen.insert(processIdentifier).inserted {
                ordered.append(processIdentifier)
            }
        }
        return ordered
    }

    private func windowElements(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func setBoolean(_ value: Bool, attribute: String, on element: AXUIElement) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean)
    }
}
