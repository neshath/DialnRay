import AppKit
import DialnRayCore

struct OverlaySnapshot {
    var screenFrame: CGRect
    var anchor: CGPoint
    var pointer: CGPoint
    var activeQuadrant: TargetQuadrant?
    var activeZone: DialTargetZone?
    var openApps: [OpenAppSummary]
    var selectedAppID: UUID?
    var ranked: [RankedTarget]
    var selected: TargetCandidate?
    var phase: InteractionPhase
    var dwellProgress: Double
    var dwellRemaining: TimeInterval
    var scanSummary: ScanSummary?
    var diagnosticsVisible: Bool
    var rayIntensity: Double
    var reduceMotion: Bool
    var reduceTransparency: Bool
    var increaseContrast: Bool
}

@MainActor
final class OverlayWindowController {
    private var panel: NSPanel?
    private var overlayView: OverlayView?

    func show(on screen: NSScreen, snapshot: OverlaySnapshot) {
        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.setFrame(screen.frame, display: true)
        } else {
            panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            panel.contentView = view
            self.panel = panel
            self.overlayView = view
        }
        overlayView?.snapshot = snapshot
        panel.orderFrontRegardless()
    }

    func update(_ snapshot: OverlaySnapshot) {
        overlayView?.snapshot = snapshot
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
