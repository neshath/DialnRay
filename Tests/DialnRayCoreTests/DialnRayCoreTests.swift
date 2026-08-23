import CoreGraphics
import Foundation
import Testing
@testable import DialnRayCore

@Test func rankerPrefersPointerDirection() {
    let east = TargetCandidate(label: "East", role: "button", frame: CGRect(x: 300, y: 90, width: 20, height: 20), source: .accessibility, confidence: 1)
    let north = TargetCandidate(label: "North", role: "button", frame: CGRect(x: 90, y: 300, width: 20, height: 20), source: .accessibility, confidence: 1)
    let ranked = TargetRanker.rank(targets: [north, east], anchor: CGPoint(x: 100, y: 100), pointer: CGPoint(x: 170, y: 100))
    #expect(ranked.first?.target.id == east.id)
}

@Test func rankerLimitsCandidateCount() {
    let targets = (0..<20).map { index in
        TargetCandidate(label: "\(index)", role: "button", frame: CGRect(x: 150 + index * 10, y: 100, width: 10, height: 10), source: .layout, confidence: 0.8)
    }
    #expect(TargetRanker.rank(targets: targets, anchor: .zero, pointer: CGPoint(x: 100, y: 0), maximumCount: 8).count == 8)
}

@Test func rankerUsesPointerDistanceToDisambiguateCollinearTargets() {
    let near = TargetCandidate(label: "Near", role: "button", frame: CGRect(x: 90, y: -10, width: 20, height: 20), source: .accessibility, confidence: 1)
    let far = TargetCandidate(label: "Far", role: "button", frame: CGRect(x: 390, y: -10, width: 20, height: 20), source: .accessibility, confidence: 1)
    let ranked = TargetRanker.rank(targets: [near, far], anchor: .zero, pointer: CGPoint(x: 400, y: 0))
    #expect(ranked.first?.target.id == far.id)
}

@Test func dialEdgeSelectsFarthestCollinearTarget() {
    let near = TargetCandidate(label: "Near", role: "button", frame: CGRect(x: 190, y: -10, width: 20, height: 20), source: .accessibility, confidence: 1)
    let far = TargetCandidate(label: "Far", role: "button", frame: CGRect(x: 590, y: -10, width: 20, height: 20), source: .accessibility, confidence: 1)
    let pointer = CGPoint(x: DialGeometry.outerRadius, y: 0)
    let ranked = TargetRanker.rank(targets: [near, far], anchor: .zero, pointer: pointer)
    #expect(ranked.first?.target.id == far.id)
}

@Test func rankerPrioritizesIndividualLinksInLinkDenseRegions() {
    let links = (0..<4).map { index in
        TargetCandidate(
            label: "Article link \(index)",
            role: "Link",
            frame: CGRect(x: 540 + index * 10, y: -10, width: 20, height: 20),
            source: .accessibility,
            confidence: 1
        )
    }
    let surroundingButton = TargetCandidate(
        label: "Page control",
        role: "Button",
        frame: CGRect(x: 590, y: -10, width: 20, height: 20),
        source: .accessibility,
        confidence: 1
    )

    let ranked = TargetRanker.rank(
        targets: links + [surroundingButton],
        anchor: .zero,
        pointer: CGPoint(x: DialGeometry.outerRadius, y: 0)
    )

    #expect(ranked.first?.target.role == "Link")
}

@Test func rankerRestrictsTargetsToTheActiveQuadrant() {
    let topRight = TargetCandidate(label: "Top right", role: "button", frame: CGRect(x: 90, y: 90, width: 20, height: 20), source: .accessibility, confidence: 1)
    let topLeft = TargetCandidate(label: "Top left", role: "button", frame: CGRect(x: -110, y: 90, width: 20, height: 20), source: .accessibility, confidence: 1)
    let quadrant = TargetRanker.quadrant(anchor: .zero, pointer: CGPoint(x: 30, y: 30))
    #expect(quadrant == .northEast)
    #expect(TargetRanker.targets([topRight, topLeft], in: quadrant!, anchor: .zero) == [topRight])
    #expect(TargetRanker.quadrant(anchor: .zero, pointer: CGPoint(x: 5, y: 5)) == nil)
}

@Test func dialRingsSeparateTopBarFromPageTargets() {
    let window = CGRect(x: 0, y: 0, width: 1_200, height: 800)
    let pageLink = TargetCandidate(label: "Article", role: "Link", frame: CGRect(x: 700, y: 500, width: 80, height: 24), source: .accessibility, confidence: 1)
    let addressField = TargetCandidate(label: "Address", role: "TextField", frame: CGRect(x: 500, y: 730, width: 320, height: 32), source: .accessibility, confidence: 1)

    #expect(TargetRanker.zone(anchor: .zero, pointer: CGPoint(x: 40, y: 0)) == .content)
    #expect(TargetRanker.zone(anchor: .zero, pointer: CGPoint(x: 72, y: 0)) == .topBar)
    #expect(TargetRanker.targets([pageLink, addressField], in: .content, windowFrame: window) == [pageLink])
    #expect(TargetRanker.targets([pageLink, addressField], in: .topBar, windowFrame: window) == [addressField])
}

@Test func appRingMapsClockwiseSegmentsFromTheTop() {
    let radius = DialGeometry.appRingInnerRadius + 10
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: 0, y: radius), itemCount: 4) == 0)
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: radius, y: 0), itemCount: 4) == 1)
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: 0, y: -radius), itemCount: 4) == 2)
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: -radius, y: 0), itemCount: 4) == 3)
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: 40, y: 0), itemCount: 4) == nil)
}

@Test func appRingSelectsOnlyInsideItsVisibleAnnulus() {
    let innerEdge = DialGeometry.appRingInnerRadius
    let outerEdge = DialGeometry.appRingOuterRadius

    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: 0, y: innerEdge - 0.1), itemCount: 4) == nil)
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: 0, y: innerEdge), itemCount: 4) == 0)
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: 0, y: outerEdge), itemCount: 4) == 0)
    #expect(AppRingSelector.index(anchor: .zero, pointer: CGPoint(x: 0, y: outerEdge + 0.1), itemCount: 4) == nil)
}

@Test func pointerFilterSmoothsMovement() {
    var filter = PointerFilter(smoothing: 0.75)
    _ = filter.update(.zero)
    let point = filter.update(CGPoint(x: 100, y: 40))
    #expect(point.x == 25)
    #expect(point.y == 10)
}

@Test func dwellResetsAfterExcessiveJitter() {
    let id = UUID()
    var dwell = DwellEngine(duration: 1, jitterTolerance: 10)
    _ = dwell.update(targetID: id, pointer: .zero, now: 0)
    let progress = dwell.update(targetID: id, pointer: CGPoint(x: 20, y: 0), now: 0.8)
    #expect(progress.paused)
    #expect(progress.progress == 0)
    #expect(!progress.completed)
}

@Test func dwellCompletesAfterDuration() {
    let id = UUID()
    var dwell = DwellEngine(duration: 0.8, jitterTolerance: 16)
    _ = dwell.update(targetID: id, pointer: .zero, now: 10)
    let progress = dwell.update(targetID: id, pointer: CGPoint(x: 2, y: 1), now: 10.8)
    #expect(progress.completed)
}

@Test func profileLearnsSuccessfulSource() {
    var profile = AppScanProfile(bundleIdentifier: "com.example.app")
    profile.record(source: .vision, targetCount: 7)
    profile.record(source: .accessibility, targetCount: 0)
    #expect(profile.preferredSources.first == .vision)
}

@Test func endedSubscriptionIsNotEntitled() {
    let purchase = GumroadPurchase(productID: "p", productName: "DialnRay", email: nil, recurrence: "yearly", refunded: false, disputed: false, chargebacked: false, subscriptionEndedAt: "2026-01-01", subscriptionCancelledAt: nil, subscriptionFailedAt: nil)
    #expect(!purchase.isEntitled)
}
