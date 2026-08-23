import AppKit
import DialnRayCore

final class OverlayView: NSView {
    private var iconCache: [String: NSImage] = [:]

    var snapshot: OverlaySnapshot? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let snapshot else { return }
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()

        NSColor(calibratedWhite: 0, alpha: snapshot.increaseContrast ? 0.12 : 0.035).setFill()
        bounds.fill()

        let anchor = local(snapshot.anchor, in: snapshot.screenFrame)
        drawRays(snapshot, anchor: anchor)
        drawTargetRings(snapshot)
        drawAppRing(snapshot, anchor: anchor)
        drawDial(snapshot, anchor: anchor)
        if let selected = snapshot.selected {
            drawSelectionLabel(snapshot, target: selected)
        } else if let selectedApp = snapshot.openApps.first(where: { $0.id == snapshot.selectedAppID }) {
            drawAppSelectionLabel(snapshot, app: selectedApp, anchor: anchor)
        }
        if snapshot.diagnosticsVisible {
            drawDiagnostics(snapshot)
        }

        context?.restoreGState()
    }

    private func drawRays(_ snapshot: OverlaySnapshot, anchor: CGPoint) {
        for item in snapshot.ranked.reversed() {
            let target = local(item.target.center, in: snapshot.screenFrame)
            let selected = item.target.id == snapshot.selected?.id
            let path = NSBezierPath()
            path.move(to: anchor)
            path.line(to: target)
            path.lineCapStyle = .round
            path.lineWidth = selected ? 5.5 : 2.5
            NSColor(calibratedWhite: 0.02, alpha: selected ? 0.68 : 0.28).setStroke()
            path.stroke()
            path.lineWidth = selected ? 3 : 0.9
            let alpha = selected ? 1 : max(0.16, 0.42 * snapshot.rayIntensity)
            (selected ? DialnRayTheme.selectedRay : DialnRayTheme.target)
                .withAlphaComponent(alpha)
                .setStroke()
            path.stroke()
        }
    }

    private func drawTargetRings(_ snapshot: OverlaySnapshot) {
        for item in snapshot.ranked {
            let rect = local(item.target.frame, in: snapshot.screenFrame).insetBy(dx: -5, dy: -5)
            let selected = item.target.id == snapshot.selected?.id
            let path = NSBezierPath(roundedRect: rect, xRadius: min(8, rect.height / 3), yRadius: min(8, rect.height / 3))
            path.lineWidth = selected ? 4.5 : 3
            NSColor(calibratedWhite: 0.02, alpha: selected ? 0.62 : 0.42).setStroke()
            path.stroke()
            path.lineWidth = selected ? 2 : 1
            (selected ? DialnRayTheme.selectedRay : DialnRayTheme.target.withAlphaComponent(0.62)).setStroke()
            path.stroke()

            let nodeRadius: CGFloat = selected ? 5 : 3
            let node = NSBezierPath(ovalIn: CGRect(
                x: rect.midX - nodeRadius,
                y: rect.midY - nodeRadius,
                width: nodeRadius * 2,
                height: nodeRadius * 2
            ))
            (selected ? DialnRayTheme.selectedRay : DialnRayTheme.surfaceRaised).setFill()
            node.fill()
            (selected ? DialnRayTheme.selectedRay : DialnRayTheme.target).setStroke()
            node.lineWidth = 1
            node.stroke()
        }
    }

    private func drawDial(_ snapshot: OverlaySnapshot, anchor: CGPoint) {
        let radius = DialGeometry.outerRadius
        let outer = NSBezierPath(ovalIn: CGRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2))
        DialnRayTheme.surface.withAlphaComponent(snapshot.reduceTransparency ? 1 : 0.82).setFill()
        outer.fill()
        let topBarActive = snapshot.activeZone == .topBar
        (topBarActive ? DialnRayTheme.target : DialnRayTheme.hairline).setStroke()
        outer.lineWidth = topBarActive || snapshot.increaseContrast ? 2 : 1
        outer.stroke()

        if topBarActive {
            DialnRayTheme.target.withAlphaComponent(0.08).setFill()
            outer.fill()
        }

        let contentRadius = DialGeometry.contentBoundaryRadius
        let contentRect = CGRect(
            x: anchor.x - contentRadius,
            y: anchor.y - contentRadius,
            width: contentRadius * 2,
            height: contentRadius * 2
        )
        let contentRing = NSBezierPath(ovalIn: contentRect)
        DialnRayTheme.surfaceRaised.withAlphaComponent(snapshot.reduceTransparency ? 1 : 0.92).setFill()
        contentRing.fill()
        let contentActive = snapshot.activeZone == .content
        (contentActive ? DialnRayTheme.target : DialnRayTheme.hairline.withAlphaComponent(0.9)).setStroke()
        contentRing.lineWidth = contentActive || snapshot.increaseContrast ? 2 : 1
        contentRing.stroke()

        for index in 0..<24 {
            let angle = CGFloat(index) / 24 * .pi * 2
            let innerRadius: CGFloat = index.isMultiple(of: 3) ? radius - 13 : radius - 9
            let path = NSBezierPath()
            path.move(to: CGPoint(x: anchor.x + cos(angle) * innerRadius, y: anchor.y + sin(angle) * innerRadius))
            path.line(to: CGPoint(x: anchor.x + cos(angle) * (radius - 4), y: anchor.y + sin(angle) * (radius - 4)))
            path.lineWidth = index.isMultiple(of: 3) ? 1.4 : 1
            (snapshot.selected == nil ? DialnRayTheme.muted : DialnRayTheme.target)
                .withAlphaComponent(index.isMultiple(of: 3) ? 0.8 : 0.36)
                .setStroke()
            path.stroke()
        }

        drawText(
            "BAR",
            in: CGRect(x: anchor.x - 24, y: anchor.y + 64, width: 48, height: 12),
            font: DialnRayTheme.font(9, weight: .semibold),
            color: topBarActive ? DialnRayTheme.target : DialnRayTheme.muted,
            alignment: .center
        )
        drawText(
            "PAGE",
            in: CGRect(x: anchor.x - 24, y: anchor.y + 38, width: 48, height: 12),
            font: DialnRayTheme.font(9, weight: .semibold),
            color: contentActive ? DialnRayTheme.target : DialnRayTheme.muted,
            alignment: .center
        )

        let centerRadius: CGFloat = 17
        let centerRect = CGRect(
            x: anchor.x - centerRadius,
            y: anchor.y - centerRadius,
            width: centerRadius * 2,
            height: centerRadius * 2
        )
        let center = NSBezierPath(ovalIn: centerRect)
        DialnRayTheme.surfaceRaised.setFill()
        center.fill()
        DialnRayTheme.target.setStroke()
        center.lineWidth = 2
        center.stroke()

        if snapshot.dwellProgress > 0 {
            let progressPath = NSBezierPath()
            let progressRadius = snapshot.selectedAppID == nil
                ? radius + 7
                : DialGeometry.appRingOuterRadius + 7
            progressPath.appendArc(
                withCenter: anchor,
                radius: progressRadius,
                startAngle: 90,
                endAngle: 90 - CGFloat(snapshot.dwellProgress * 360),
                clockwise: true
            )
            progressPath.lineCapStyle = .round
            progressPath.lineWidth = 3
            (snapshot.dwellProgress >= 1 ? DialnRayTheme.ready : DialnRayTheme.target).setStroke()
            progressPath.stroke()
        }
    }

    private func drawAppRing(_ snapshot: OverlaySnapshot, anchor: CGPoint) {
        guard !snapshot.openApps.isEmpty else { return }
        let count = snapshot.openApps.count
        let slice = 360 / CGFloat(count)
        let gap = min(3.2, slice * 0.12)
        let innerRadius = DialGeometry.appRingInnerRadius
        let outerRadius = DialGeometry.appRingOuterRadius

        for (index, app) in snapshot.openApps.enumerated() {
            let start = 90 - CGFloat(index) * slice - gap / 2
            let end = 90 - CGFloat(index + 1) * slice + gap / 2
            let selected = app.id == snapshot.selectedAppID
            let segment = annularSegment(
                center: anchor,
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                startAngle: start,
                endAngle: end
            )
            (selected
                ? DialnRayTheme.selectedRay.withAlphaComponent(0.24)
                : DialnRayTheme.surface.withAlphaComponent(snapshot.reduceTransparency ? 1 : 0.86)
            ).setFill()
            segment.fill()
            (selected ? DialnRayTheme.selectedRay : DialnRayTheme.hairline).setStroke()
            segment.lineWidth = selected ? 2.4 : 1
            segment.stroke()

            let middle = (start + end) / 2 * .pi / 180
            let labelRadius = (innerRadius + outerRadius) / 2
            let labelCenter = CGPoint(
                x: anchor.x + cos(middle) * labelRadius,
                y: anchor.y + sin(middle) * labelRadius
            )
            let iconSize: CGFloat = count > 10 ? 16 : 21
            if let icon = icon(for: app) {
                icon.draw(
                    in: CGRect(
                        x: labelCenter.x - iconSize / 2,
                        y: labelCenter.y - 3,
                        width: iconSize,
                        height: iconSize
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: selected ? 1 : 0.82
                )
            }

            if count <= 12 {
                let arcWidth = max(42, min(88, (2 * .pi * labelRadius / CGFloat(count)) - 8))
                drawText(
                    app.appName,
                    in: CGRect(x: labelCenter.x - arcWidth / 2, y: labelCenter.y - 19, width: arcWidth, height: 13),
                    font: DialnRayTheme.font(count > 8 ? 9 : 10, weight: selected ? .semibold : .medium),
                    color: selected ? DialnRayTheme.ink : DialnRayTheme.muted,
                    alignment: .center
                )
            }

            if app.isFrontmost {
                let dotCenter = CGPoint(
                    x: anchor.x + cos(middle) * (outerRadius - 8),
                    y: anchor.y + sin(middle) * (outerRadius - 8)
                )
                DialnRayTheme.ready.setFill()
                NSBezierPath(ovalIn: CGRect(x: dotCenter.x - 2.5, y: dotCenter.y - 2.5, width: 5, height: 5)).fill()
            }
        }

        drawText(
            "APPS",
            in: CGRect(x: anchor.x - 28, y: anchor.y + outerRadius + 5, width: 56, height: 13),
            font: DialnRayTheme.font(10, weight: .semibold),
            color: snapshot.selectedAppID == nil ? DialnRayTheme.muted : DialnRayTheme.target,
            alignment: .center
        )
    }

    private func drawAppSelectionLabel(_ snapshot: OverlaySnapshot, app: OpenAppSummary, anchor: CGPoint) {
        let width: CGFloat = 220
        let height: CGFloat = 58
        let panel = CGRect(
            x: anchor.x - width / 2,
            y: max(16, anchor.y - DialGeometry.appRingOuterRadius - height - 14),
            width: width,
            height: height
        )
        drawSurface(panel, radius: 10, snapshot: snapshot)
        drawText(
            "Switch to (app.appName)",
            in: CGRect(x: panel.minX + 12, y: panel.maxY - 27, width: panel.width - 24, height: 18),
            font: DialnRayTheme.font(13, weight: .semibold),
            color: DialnRayTheme.ink
        )
        let windowLabel = app.windowCount == 1 ? "1 open window" : "\(app.windowCount) open windows"
        drawText(
            windowLabel,
            in: CGRect(x: panel.minX + 12, y: panel.minY + 10, width: panel.width - 24, height: 18),
            font: DialnRayTheme.monospacedDigits(12),
            color: statusColor(for: snapshot.phase)
        )
    }

    private func drawSelectionLabel(_ snapshot: OverlaySnapshot, target: TargetCandidate) {
        let frame = local(target.frame, in: snapshot.screenFrame)
        let width: CGFloat = 220
        let height: CGFloat = 58
        var x = frame.maxX + 12
        if x + width > bounds.maxX - (snapshot.diagnosticsVisible ? 270 : 16) {
            x = max(16, frame.minX - width - 12)
        }
        let y = min(max(frame.midY - height / 2, 16), bounds.maxY - height - 16)
        let panel = CGRect(x: x, y: y, width: width, height: height)
        drawSurface(panel, radius: 10, snapshot: snapshot)

        drawText(
            "Selected: \(target.label)",
            in: CGRect(x: panel.minX + 12, y: panel.maxY - 27, width: panel.width - 24, height: 18),
            font: DialnRayTheme.font(13, weight: .semibold),
            color: DialnRayTheme.ink
        )
        let secondary: String
        switch snapshot.phase {
        case .latched:
            secondary = snapshot.dwellProgress >= 1
                ? "Latched · Return to activate"
                : "Activating in \(String(format: "%.1fs", snapshot.dwellRemaining))"
        case .activated:
            secondary = "Activated"
        case .failed(let message):
            secondary = message
        default:
            secondary = "Hold direction · Esc to cancel"
        }
        drawText(
            secondary,
            in: CGRect(x: panel.minX + 12, y: panel.minY + 10, width: panel.width - 24, height: 18),
            font: DialnRayTheme.monospacedDigits(12),
            color: statusColor(for: snapshot.phase)
        )
    }

    private func drawDiagnostics(_ snapshot: OverlaySnapshot) {
        let railWidth: CGFloat = 240
        let railHeight: CGFloat = snapshot.scanSummary?.degradedReason == nil ? 290 : 326
        let rail = CGRect(
            x: bounds.maxX - railWidth - 24,
            y: bounds.midY - railHeight / 2,
            width: railWidth,
            height: railHeight
        )
        drawSurface(rail, radius: 14, snapshot: snapshot)
        var y = rail.maxY - 34

        drawText("DialnRay", in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 22), font: DialnRayTheme.font(17, weight: .semibold), color: DialnRayTheme.ink)
        y -= 35
        let appName = snapshot.scanSummary?.app.displayName ?? "Recognizing app…"
        drawRow(symbol: "◉", label: appName, value: nil, y: y, rail: rail, color: DialnRayTheme.ink)
        y -= 34
        drawDivider(y: y, rail: rail)
        y -= 26
        let sources = snapshot.scanSummary?.sources.map(\.rawValue).joined(separator: " + ") ?? "Adaptive scan"
        drawText("SCAN SOURCES", in: CGRect(x: rail.minX + 16, y: y, width: 100, height: 16), font: DialnRayTheme.font(11, weight: .semibold), color: DialnRayTheme.muted)
        y -= 24
        drawText(sources, in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(13), color: DialnRayTheme.target)
        y -= 34
        drawDivider(y: y, rail: rail)
        y -= 29
        if let selectedApp = snapshot.openApps.first(where: { $0.id == snapshot.selectedAppID }) {
            drawText("Switch to: \(selectedApp.appName)", in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(13, weight: .semibold), color: DialnRayTheme.ink)
            y -= 23
            let windows = selectedApp.windowCount == 1 ? "1 open window" : "\(selectedApp.windowCount) open windows"
            drawText("\(windows) · APPS ring", in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(12), color: DialnRayTheme.muted)
        } else if let selected = snapshot.selected {
            drawText("Selected: \(selected.label)", in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(13, weight: .semibold), color: DialnRayTheme.ink)
            y -= 23
            drawText("\(selected.role) · \(Int(selected.confidence * 100))% confidence", in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(12), color: DialnRayTheme.muted)
        } else {
            let guidance = snapshot.activeQuadrant == nil
                ? "Move into a quadrant"
                : "Move outward to select"
            drawText(guidance, in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(13), color: DialnRayTheme.muted)
            y -= 23
            let targetSummary = snapshot.activeQuadrant.map {
                let zone = snapshot.activeZone?.displayName ?? "Neutral"
                return "\(zone) · \($0.displayName) · \(snapshot.ranked.count)"
            } ?? "Rays hidden at center"
            drawText(targetSummary, in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(12), color: DialnRayTheme.muted)
        }
        y -= 38
        drawRow(symbol: phaseSymbol(snapshot.phase), label: phaseLabel(snapshot.phase), value: countdownText(snapshot), y: y, rail: rail, color: statusColor(for: snapshot.phase))
        y -= 36
        drawText("Esc to cancel · Return to confirm", in: CGRect(x: rail.minX + 16, y: y, width: rail.width - 32, height: 18), font: DialnRayTheme.font(12), color: DialnRayTheme.muted)

        if let reason = snapshot.scanSummary?.degradedReason {
            y -= 42
            drawText(reason, in: CGRect(x: rail.minX + 16, y: y - 12, width: rail.width - 32, height: 42), font: DialnRayTheme.font(11), color: DialnRayTheme.warning)
        }
    }

    private func drawSurface(_ rect: CGRect, radius: CGFloat, snapshot: OverlaySnapshot) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let surface = snapshot.reduceTransparency ? DialnRayTheme.surfaceRaised : DialnRayTheme.surface
        surface.setFill()
        path.fill()
        (snapshot.increaseContrast ? DialnRayTheme.ink.withAlphaComponent(0.45) : DialnRayTheme.hairline).setStroke()
        path.lineWidth = snapshot.increaseContrast ? 2 : 1
        path.stroke()
    }

    private func annularSegment(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) -> NSBezierPath {
        let startRadians = startAngle * .pi / 180
        let endRadians = endAngle * .pi / 180
        let path = NSBezierPath()
        path.move(to: CGPoint(
            x: center.x + cos(startRadians) * innerRadius,
            y: center.y + sin(startRadians) * innerRadius
        ))
        path.line(to: CGPoint(
            x: center.x + cos(startRadians) * outerRadius,
            y: center.y + sin(startRadians) * outerRadius
        ))
        path.appendArc(withCenter: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        path.line(to: CGPoint(
            x: center.x + cos(endRadians) * innerRadius,
            y: center.y + sin(endRadians) * innerRadius
        ))
        path.appendArc(withCenter: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: false)
        path.close()
        return path
    }

    private func icon(for app: OpenAppSummary) -> NSImage? {
        if let cached = iconCache[app.bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[app.bundleIdentifier] = icon
        return icon
    }

    private func drawRow(symbol: String, label: String, value: String?, y: CGFloat, rail: CGRect, color: NSColor) {
        drawText(symbol, in: CGRect(x: rail.minX + 16, y: y, width: 18, height: 18), font: DialnRayTheme.font(13, weight: .semibold), color: color)
        drawText(label, in: CGRect(x: rail.minX + 40, y: y, width: value == nil ? rail.width - 56 : 116, height: 18), font: DialnRayTheme.font(13, weight: .medium), color: color)
        if let value {
            drawText(value, in: CGRect(x: rail.maxX - 78, y: y, width: 62, height: 18), font: DialnRayTheme.monospacedDigits(12), color: color, alignment: .right)
        }
    }

    private func drawDivider(y: CGFloat, rail: CGRect) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rail.minX + 16, y: y))
        path.line(to: CGPoint(x: rail.maxX - 16, y: y))
        path.lineWidth = 1
        DialnRayTheme.hairline.setStroke()
        path.stroke()
    }

    private func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    private func statusColor(for phase: InteractionPhase) -> NSColor {
        switch phase {
        case .activated: return DialnRayTheme.ready
        case .failed: return DialnRayTheme.error
        case .latched: return DialnRayTheme.target
        case .scanning: return DialnRayTheme.warning
        default: return DialnRayTheme.muted
        }
    }

    private func phaseLabel(_ phase: InteractionPhase) -> String {
        switch phase {
        case .idle: return "Ready"
        case .scanning: return "Scanning"
        case .tracking: return "Tracking"
        case .selected: return "Selected"
        case .latched: return "Latched"
        case .activated: return "Activated"
        case .failed: return "Needs attention"
        }
    }

    private func phaseSymbol(_ phase: InteractionPhase) -> String {
        switch phase {
        case .activated: return "✓"
        case .failed: return "!"
        case .latched: return "◎"
        case .scanning: return "…"
        default: return "○"
        }
    }

    private func countdownText(_ snapshot: OverlaySnapshot) -> String? {
        guard case .latched = snapshot.phase else { return nil }
        return String(format: "%.1fs", snapshot.dwellRemaining)
    }

    private func local(_ point: CGPoint, in screen: CGRect) -> CGPoint {
        CGPoint(x: point.x - screen.minX, y: point.y - screen.minY)
    }

    private func local(_ rect: CGRect, in screen: CGRect) -> CGRect {
        CGRect(x: rect.minX - screen.minX, y: rect.minY - screen.minY, width: rect.width, height: rect.height)
    }
}
