import CoreGraphics
import Foundation

public struct PointerFilter: Sendable {
    public var smoothing: Double
    public private(set) var point: CGPoint?

    public init(smoothing: Double = 0.72) {
        self.smoothing = min(max(smoothing, 0), 0.95)
    }

    public mutating func reset(to point: CGPoint? = nil) {
        self.point = point
    }

    public mutating func update(_ input: CGPoint) -> CGPoint {
        guard let current = point else {
            point = input
            return input
        }
        let response = 1 - smoothing
        let filtered = CGPoint(
            x: current.x + (input.x - current.x) * response,
            y: current.y + (input.y - current.y) * response
        )
        point = filtered
        return filtered
    }
}
