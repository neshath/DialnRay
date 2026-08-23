import CoreGraphics
import Foundation

public struct RankedTarget: Equatable, Sendable {
    public var target: TargetCandidate
    public var score: Double
    public var angularDistance: Double
    public var distance: Double
}

public enum DialGeometry {
    public static let deadZoneRadius: CGFloat = 20
    public static let contentBoundaryRadius: CGFloat = 58
    public static let outerRadius: CGFloat = 84
    public static let appRingInnerRadius: CGFloat = 102
    public static let appRingOuterRadius: CGFloat = 148
    public static let directPointingThreshold: CGFloat = 112
}

public enum AppRingSelector {
    public static func index(
        anchor: CGPoint,
        pointer: CGPoint,
        itemCount: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }
        let dx = pointer.x - anchor.x
        let dy = pointer.y - anchor.y
        let distance = hypot(dx, dy)
        guard distance >= DialGeometry.appRingInnerRadius,
              distance <= DialGeometry.appRingOuterRadius else { return nil }
        let angle = atan2(dy, dx)
        let clockwiseFromTop = positiveRemainder(.pi / 2 - angle, modulus: .pi * 2)
        let slice = (.pi * 2) / CGFloat(itemCount)
        return min(Int(clockwiseFromTop / slice), itemCount - 1)
    }

    private static func positiveRemainder(_ value: CGFloat, modulus: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }
}

public enum DialTargetZone: String, Equatable, Sendable {
    case content
    case topBar

    public var displayName: String {
        switch self {
        case .content: return "Page / Window"
        case .topBar: return "Top bar"
        }
    }
}

public enum TargetQuadrant: String, Equatable, Sendable {
    case northEast
    case northWest
    case southEast
    case southWest

    public var displayName: String {
        switch self {
        case .northEast: return "Top right"
        case .northWest: return "Top left"
        case .southEast: return "Bottom right"
        case .southWest: return "Bottom left"
        }
    }
}

public enum TargetRanker {
    public static func zone(
        anchor: CGPoint,
        pointer: CGPoint,
        deadZone: CGFloat = DialGeometry.deadZoneRadius
    ) -> DialTargetZone? {
        let magnitude = hypot(pointer.x - anchor.x, pointer.y - anchor.y)
        guard magnitude >= deadZone else { return nil }
        return magnitude >= DialGeometry.contentBoundaryRadius ? .topBar : .content
    }

    public static func quadrant(
        anchor: CGPoint,
        pointer: CGPoint,
        deadZone: CGFloat = DialGeometry.deadZoneRadius
    ) -> TargetQuadrant? {
        let dx = pointer.x - anchor.x
        let dy = pointer.y - anchor.y
        guard hypot(dx, dy) >= deadZone else { return nil }
        switch (dx >= 0, dy >= 0) {
        case (true, true): return .northEast
        case (false, true): return .northWest
        case (true, false): return .southEast
        case (false, false): return .southWest
        }
    }

    public static func targets(
        _ targets: [TargetCandidate],
        in quadrant: TargetQuadrant,
        anchor: CGPoint
    ) -> [TargetCandidate] {
        targets.filter {
            self.quadrant(anchor: anchor, pointer: $0.center, deadZone: 0) == quadrant
        }
    }

    public static func targets(
        _ targets: [TargetCandidate],
        in zone: DialTargetZone,
        windowFrame: CGRect
    ) -> [TargetCandidate] {
        let topBarDepth = min(max(windowFrame.height * 0.12, 96), 132)
        let topBarThreshold = windowFrame.maxY - topBarDepth
        return targets.filter { target in
            let isTopBar = target.center.y >= topBarThreshold
            return zone == .topBar ? isTopBar : !isTopBar
        }
    }

    public static func rank(
        targets: [TargetCandidate],
        anchor: CGPoint,
        pointer: CGPoint,
        maximumCount: Int = 8
    ) -> [RankedTarget] {
        guard maximumCount > 0 else { return [] }
        let pointerVector = vector(from: anchor, to: pointer)
        let pointerMagnitude = hypot(pointerVector.dx, pointerVector.dy)
        let hasDirection = pointerMagnitude >= 10
        let targetDistances = targets.map {
            hypot($0.center.x - anchor.x, $0.center.y - anchor.y)
        }
        let minimumDistance = targetDistances.min() ?? 0
        let maximumDistance = targetDistances.max() ?? minimumDistance
        let radialStart = pointerMagnitude >= DialGeometry.contentBoundaryRadius
            ? DialGeometry.contentBoundaryRadius
            : DialGeometry.deadZoneRadius
        let radialEnd = pointerMagnitude >= DialGeometry.contentBoundaryRadius
            ? DialGeometry.outerRadius
            : DialGeometry.contentBoundaryRadius
        let radialTravel = radialEnd - radialStart
        let dialProgress = min(max((pointerMagnitude - radialStart) / radialTravel, 0), 1)
        let dialDesiredDistance = minimumDistance + (maximumDistance - minimumDistance) * dialProgress
        let directPointing = pointerMagnitude > DialGeometry.directPointingThreshold
        let linkCount = targets.lazy.filter { isLink($0) }.count
        let prioritizeLinks = linkCount >= 4

        return targets.compactMap { target -> RankedTarget? in
            let targetVector = vector(from: anchor, to: target.center)
            let distance = hypot(targetVector.dx, targetVector.dy)
            guard distance >= 1 else { return nil }

            let angle = hasDirection
                ? angularDistance(pointerVector, targetVector)
                : 0
            let angleScore = hasDirection ? max(0, 1 - angle / .pi) : 0.72
            let radialMatchScore = 1 / (1 + abs(distance - dialDesiredDistance) / 120)
            let pointerDistance = hypot(target.center.x - pointer.x, target.center.y - pointer.y)
            let pointerProximityScore = 1 / (1 + pointerDistance / 160)
            let sourceBoost: Double
            switch target.source {
            case .accessibility: sourceBoost = 1
            case .layout: sourceBoost = 0.88
            case .vision: sourceBoost = 0.78
            }
            // In link-dense regions, prefer the semantic hyperlink itself over
            // nearby generic containers. Radial distance still orders links
            // from near to far as the pointer moves toward the dial edge.
            let semanticBoost = prioritizeLinks && isLink(target) ? 0.10 : 0
            let score: Double
            if directPointing {
                score = (angleScore * 0.30)
                    + (pointerProximityScore * 0.45)
                    + (target.confidence * 0.20)
                    + (sourceBoost * 0.05)
                    + semanticBoost
            } else {
                score = (angleScore * 0.47)
                    + (radialMatchScore * 0.28)
                    + (pointerProximityScore * 0.08)
                    + (target.confidence * 0.12)
                    + (sourceBoost * 0.05)
                    + semanticBoost
            }

            return RankedTarget(
                target: target,
                score: score,
                angularDistance: angle,
                distance: distance
            )
        }
        .sorted {
            if abs($0.score - $1.score) < 0.0001 {
                return $0.distance < $1.distance
            }
            return $0.score > $1.score
        }
        .prefix(maximumCount)
        .map { $0 }
    }

    public static func selected(
        from ranked: [RankedTarget],
        maximumAngularDistance: Double = .pi / 5
    ) -> TargetCandidate? {
        guard let first = ranked.first,
              first.angularDistance <= maximumAngularDistance else {
            return nil
        }
        return first.target
    }

    private static func vector(from start: CGPoint, to end: CGPoint) -> CGVector {
        CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private static func angularDistance(_ lhs: CGVector, _ rhs: CGVector) -> Double {
        let lhsAngle = atan2(lhs.dy, lhs.dx)
        let rhsAngle = atan2(rhs.dy, rhs.dx)
        let raw = abs(lhsAngle - rhsAngle).truncatingRemainder(dividingBy: .pi * 2)
        return min(raw, .pi * 2 - raw)
    }

    private static func isLink(_ target: TargetCandidate) -> Bool {
        target.role.caseInsensitiveCompare("Link") == .orderedSame
    }
}
