import AppKit
import DialnRayCore
import Foundation

@MainActor
final class AppCoordinator {
    let settings: SettingsStore
    let permissions: PermissionManager
    let license: LicenseService

    var onNeedsSettings: (() -> Void)?
    var onStateChanged: (() -> Void)?

    private let scanner = AdaptiveScanner()
    private let activator = TargetActivator()
    private let windowSwitcher = WindowSwitcher()
    private let overlay = OverlayWindowController()
    private let input = InputMonitor()
    private var scanResult: AdaptiveScanResult?
    private var screen: NSScreen?
    private var anchor = CGPoint.zero
    private var pointer = CGPoint.zero
    private var filter = PointerFilter()
    private var dwell = DwellEngine()
    private var phase: InteractionPhase = .idle
    private var selected: DiscoveredTarget?
    private var openApps: [OpenAppTarget] = []
    private var selectedApp: OpenAppTarget?
    private var ranked: [RankedTarget] = []
    private var dwellProgress = DwellProgress(targetID: nil, progress: 0, completed: false, paused: false)
    private var autoClickNeedsRearm = false
    private var appSwitchNeedsRearm = false
    private var timer: Timer?

    init(settings: SettingsStore, permissions: PermissionManager, license: LicenseService) {
        self.settings = settings
        self.permissions = permissions
        self.license = license
        input.onToggle = { [weak self] in self?.toggleOverlay() }
        input.onCancel = { [weak self] in self?.cancelOverlay() }
        input.onConfirm = { [weak self] in self?.confirmSelection() }
        input.onPointer = { [weak self] point in self?.pointerMoved(to: point) }
    }

    var isOverlayActive: Bool { screen != nil }

    func start() {
        input.start()
        Task { await license.refreshIfNeeded() }
    }

    func stop() {
        timer?.invalidate()
        input.stop()
    }

    func toggleOverlay() {
        isOverlayActive ? cancelOverlay() : activateOverlay()
    }

    func activateOverlay() {
        permissions.refresh()
        guard permissions.accessibilityTrusted else {
            permissions.requestAccessibility()
            onNeedsSettings?()
            return
        }
        input.refreshAfterPermissionChange()
        guard license.canUseProduct else {
            onNeedsSettings?()
            return
        }

        let invocationPoint = NSEvent.mouseLocation
        guard let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(invocationPoint) }) ?? NSScreen.main else { return }
        let screenCenter = CGPoint(x: activeScreen.frame.midX, y: activeScreen.frame.midY)
        screen = activeScreen
        anchor = screenCenter
        pointer = screenCenter
        filter = PointerFilter(smoothing: settings.smoothing)
        filter.reset(to: screenCenter)
        CGWarpMouseCursorPosition(ScreenGeometry.cgPointFromAppKit(screenCenter))
        dwell = DwellEngine(duration: settings.dwellDuration, jitterTolerance: settings.jitterTolerance)
        phase = .scanning
        scanResult = nil
        openApps = windowSwitcher.openApplications(excludingBundleIdentifier: Bundle.main.bundleIdentifier)
        ranked = []
        selected = nil
        selectedApp = nil
        autoClickNeedsRearm = false
        appSwitchNeedsRearm = false
        dwellProgress = DwellProgress(targetID: nil, progress: 0, completed: false, paused: false)
        input.overlayActive = true
        input.textEntryActive = false
        overlay.show(on: activeScreen, snapshot: makeSnapshot())
        startTimer()
        onStateChanged?()

        Task { [weak self] in
            guard let self else { return }
            let result = await scanner.scan(cursor: screenCenter, settings: settings)
            guard isOverlayActive else { return }
            scanResult = result
            phase = result == nil || result?.discoveredTargets.isEmpty == true
                ? .failed("No actionable controls were recognized in this window.")
                : .tracking
            evaluate(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func previewOverlay() {
        let cursor = NSEvent.mouseLocation
        guard let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main else { return }
        screen = activeScreen
        anchor = CGPoint(x: activeScreen.frame.midX, y: activeScreen.frame.midY)
        pointer = CGPoint(x: anchor.x, y: anchor.y + 122)
        let previewApps = ["Calendar", "Safari", "ChatGPT", "Finder"]
        openApps = previewApps.enumerated().map { index, name in
            let summary = OpenAppSummary(
                id: UUID(),
                processIdentifier: NSRunningApplication.current.processIdentifier,
                bundleIdentifier: "com.dialnray.preview.\(index)",
                appName: name,
                windowCount: index == 1 ? 2 : 1,
                isFrontmost: index == 2
            )
            return OpenAppTarget(summary: summary, application: .current, windows: [])
        }
        selectedApp = openApps.first
        let previewTopBarY = activeScreen.visibleFrame.maxY - 70
        let frames = [
            ("New task", CGRect(x: anchor.x + 310, y: anchor.y + 170, width: 108, height: 34), ScanSource.accessibility, 0.98),
            ("Address field", CGRect(x: anchor.x + 150, y: previewTopBarY, width: 250, height: 34), ScanSource.accessibility, 0.96),
            ("Share", CGRect(x: anchor.x + 365, y: anchor.y + 82, width: 86, height: 34), ScanSource.accessibility, 0.94),
            ("Projects", CGRect(x: anchor.x - 390, y: anchor.y + 110, width: 142, height: 32), ScanSource.layout, 0.72),
            ("Export", CGRect(x: anchor.x + 285, y: anchor.y - 155, width: 92, height: 36), ScanSource.vision, 0.68),
            ("Settings", CGRect(x: anchor.x - 330, y: anchor.y - 185, width: 118, height: 32), ScanSource.accessibility, 0.91),
        ]
        let discovered = frames.map { label, frame, source, confidence in
            DiscoveredTarget(candidate: TargetCandidate(
                label: label,
                role: "Button",
                frame: frame,
                source: source,
                confidence: confidence,
                action: .press
            ))
        }
        let app = AppContext(
            bundleIdentifier: "com.dialnray.preview",
            displayName: "Preview workspace",
            processIdentifier: 0,
            windowTitle: "Adaptive scan preview",
            windowFrame: activeScreen.visibleFrame
        )
        let summary = ScanSummary(
            app: app,
            sources: [.accessibility, .layout, .vision],
            targets: discovered.map(\.candidate),
            duration: 0.074
        )
        scanResult = AdaptiveScanResult(summary: summary, discoveredTargets: discovered)
        ranked = []
        selected = nil
        let selectedID = selectedApp?.summary.id
        dwellProgress = DwellProgress(targetID: selectedID, progress: 0.42, completed: false, paused: false)
        phase = selectedID.map { .latched($0, progress: 0.42) } ?? .tracking
        input.overlayActive = true
        overlay.show(on: activeScreen, snapshot: makeSnapshot())
        onStateChanged?()
    }

    func cancelOverlay() {
        timer?.invalidate()
        timer = nil
        overlay.hide()
        input.overlayActive = false
        input.textEntryActive = false
        screen = nil
        scanResult = nil
        selected = nil
        openApps = []
        selectedApp = nil
        ranked = []
        autoClickNeedsRearm = false
        appSwitchNeedsRearm = false
        dwell.reset()
        phase = .idle
        onStateChanged?()
    }

    func confirmSelection() {
        if let selectedApp {
            switch settings.activationMode {
            case .explicit:
                activate(selectedApp)
            case .dwellConfirm:
                if case .latched = phase, dwellProgress.completed { activate(selectedApp) }
            case .dwellAutoClick:
                if dwellProgress.completed { activate(selectedApp) }
            }
            return
        }
        guard let selected else { return }
        switch settings.activationMode {
        case .explicit:
            activate(selected)
        case .dwellConfirm:
            if case .latched = phase, dwellProgress.completed { activate(selected) }
        case .dwellAutoClick:
            if dwellProgress.completed { activate(selected) }
        }
    }

    private func pointerMoved(to point: CGPoint) {
        guard isOverlayActive else { return }
        pointer = filter.update(point)
        evaluate(now: ProcessInfo.processInfo.systemUptime)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluate(now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func evaluate(now: TimeInterval) {
        let distanceFromAnchor = hypot(pointer.x - anchor.x, pointer.y - anchor.y)
        if distanceFromAnchor >= DialGeometry.appRingInnerRadius,
           distanceFromAnchor <= DialGeometry.appRingOuterRadius {
            evaluateAppRing(now: now)
            return
        }

        // Beyond the visible APPS annulus there is no actionable segment.
        // Keep that space neutral so its angle cannot switch an application
        // or accidentally carry a dwell selection into another interaction.
        if distanceFromAnchor > DialGeometry.appRingOuterRadius {
            ranked = []
            selected = nil
            selectedApp = nil
            input.textEntryActive = false
            dwellProgress = dwell.update(targetID: nil, pointer: pointer, now: now)
            phase = .tracking
            overlay.update(makeSnapshot())
            return
        }

        if appSwitchNeedsRearm, distanceFromAnchor < DialGeometry.outerRadius {
            appSwitchNeedsRearm = false
            selectedApp = nil
            openApps = windowSwitcher.openApplications(excludingBundleIdentifier: Bundle.main.bundleIdentifier)
            dwell.reset()
            dwellProgress = DwellProgress(targetID: nil, progress: 0, completed: false, paused: false)
        } else {
            selectedApp = nil
        }

        guard let result = scanResult else {
            overlay.update(makeSnapshot())
            return
        }
        let allTargets = result.discoveredTargets.map(\.candidate)
        let activeQuadrant = TargetRanker.quadrant(anchor: anchor, pointer: pointer)
        let activeZone = TargetRanker.zone(anchor: anchor, pointer: pointer)
        let visibleTargets: [TargetCandidate]
        if let activeQuadrant, let activeZone, let windowFrame = result.summary.app.windowFrame {
            let quadrantTargets = TargetRanker.targets(allTargets, in: activeQuadrant, anchor: anchor)
            visibleTargets = TargetRanker.targets(quadrantTargets, in: activeZone, windowFrame: windowFrame)
        } else if let activeQuadrant {
            visibleTargets = TargetRanker.targets(allTargets, in: activeQuadrant, anchor: anchor)
        } else {
            visibleTargets = []
        }
        ranked = TargetRanker.rank(
            targets: visibleTargets,
            anchor: anchor,
            pointer: pointer,
            maximumCount: settings.maximumTargets
        )
        let selectedCandidate = distanceFromAnchor >= DialGeometry.deadZoneRadius
            ? TargetRanker.selected(from: ranked)
            : nil
        selected = selectedCandidate.flatMap { candidate in
            result.discoveredTargets.first(where: { $0.candidate.id == candidate.id })
        }

        guard let selected else {
            let shouldRefreshTargets = settings.activationMode == .dwellAutoClick && autoClickNeedsRearm
            autoClickNeedsRearm = false
            if shouldRefreshTargets { input.textEntryActive = false }
            dwellProgress = dwell.update(targetID: nil, pointer: pointer, now: now)
            phase = .tracking
            overlay.update(makeSnapshot())
            if shouldRefreshTargets { refreshTargets() }
            return
        }

        if settings.activationMode == .dwellAutoClick, autoClickNeedsRearm {
            phase = .activated(selected.candidate.id)
            overlay.update(makeSnapshot())
            return
        }

        switch settings.activationMode {
        case .explicit:
            dwellProgress = DwellProgress(targetID: selected.candidate.id, progress: 0, completed: false, paused: false)
            phase = .selected(selected.candidate.id)
        case .dwellConfirm, .dwellAutoClick:
            dwellProgress = dwell.update(targetID: selected.candidate.id, pointer: pointer, now: now)
            phase = .latched(selected.candidate.id, progress: dwellProgress.progress)
            if dwellProgress.completed, settings.activationMode == .dwellAutoClick {
                activate(selected)
                return
            }
        }
        overlay.update(makeSnapshot())
    }

    private func evaluateAppRing(now: TimeInterval) {
        ranked = []
        selected = nil
        input.textEntryActive = false

        guard let index = AppRingSelector.index(
            anchor: anchor,
            pointer: pointer,
            itemCount: openApps.count
        ) else {
            selectedApp = nil
            dwellProgress = dwell.update(targetID: nil, pointer: pointer, now: now)
            phase = .tracking
            overlay.update(makeSnapshot())
            return
        }

        selectedApp = openApps[index]
        guard let selectedApp else { return }
        if appSwitchNeedsRearm {
            phase = .activated(selectedApp.summary.id)
            overlay.update(makeSnapshot())
            return
        }

        switch settings.activationMode {
        case .explicit:
            dwellProgress = DwellProgress(targetID: selectedApp.summary.id, progress: 0, completed: false, paused: false)
            phase = .selected(selectedApp.summary.id)
        case .dwellConfirm, .dwellAutoClick:
            dwellProgress = dwell.update(targetID: selectedApp.summary.id, pointer: pointer, now: now)
            phase = .latched(selectedApp.summary.id, progress: dwellProgress.progress)
            if dwellProgress.completed, settings.activationMode == .dwellAutoClick {
                activate(selectedApp)
                return
            }
        }
        overlay.update(makeSnapshot())
    }

    private func activate(_ target: DiscoveredTarget) {
        do {
            try activator.activate(target)
            input.textEntryActive = target.candidate.action == .focus
            phase = .activated(target.candidate.id)
            overlay.update(makeSnapshot())
            if settings.activationMode == .dwellAutoClick {
                autoClickNeedsRearm = true
                return
            }
            timer?.invalidate()
            timer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + (settings.reduceMotion ? 0.08 : 0.24)) { [weak self] in
                self?.cancelOverlay()
            }
        } catch {
            phase = .failed(error.localizedDescription)
            overlay.update(makeSnapshot())
        }
    }

    private func activate(_ target: OpenAppTarget) {
        windowSwitcher.activate(target)
        phase = .activated(target.summary.id)
        appSwitchNeedsRearm = true
        overlay.update(makeSnapshot())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, self.isOverlayActive else { return }
            self.refreshTargets()
        }
    }

    private func refreshTargets() {
        let scanCenter = anchor
        Task { [weak self] in
            guard let self else { return }
            let result = await scanner.scan(cursor: scanCenter, settings: settings)
            guard isOverlayActive else { return }
            scanResult = result
            dwell.reset()
            dwellProgress = DwellProgress(targetID: nil, progress: 0, completed: false, paused: false)
            phase = result == nil || result?.discoveredTargets.isEmpty == true
                ? .failed("No actionable controls were recognized in this window.")
                : .tracking
            evaluate(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func makeSnapshot() -> OverlaySnapshot {
        let activeScreen = screen ?? NSScreen.main
        let appRingActive = AppRingSelector.index(
            anchor: anchor,
            pointer: pointer,
            itemCount: openApps.count
        ) != nil
        return OverlaySnapshot(
            screenFrame: activeScreen?.frame ?? .zero,
            anchor: anchor,
            pointer: pointer,
            activeQuadrant: appRingActive ? nil : TargetRanker.quadrant(anchor: anchor, pointer: pointer),
            activeZone: appRingActive ? nil : TargetRanker.zone(anchor: anchor, pointer: pointer),
            openApps: openApps.map(\.summary),
            selectedAppID: selectedApp?.summary.id,
            ranked: ranked,
            selected: selected?.candidate,
            phase: phase,
            dwellProgress: dwellProgress.progress,
            dwellRemaining: max(0, settings.dwellDuration * (1 - dwellProgress.progress)),
            scanSummary: scanResult?.summary,
            diagnosticsVisible: settings.diagnosticsVisible,
            rayIntensity: settings.rayIntensity,
            reduceMotion: settings.reduceMotion,
            reduceTransparency: settings.reduceTransparency,
            increaseContrast: settings.increaseContrast
        )
    }
}
