import CoreGraphics
import Foundation

public struct DwellProgress: Equatable, Sendable {
    public var targetID: UUID?
    public var progress: Double
    public var completed: Bool
    public var paused: Bool

    public init(targetID: UUID?, progress: Double, completed: Bool, paused: Bool) {
        self.targetID = targetID
        self.progress = progress
        self.completed = completed
        self.paused = paused
    }
}

public struct DwellEngine: Sendable {
    public var duration: TimeInterval
    public var jitterTolerance: CGFloat

    private var targetID: UUID?
    private var origin: CGPoint?
    private var startedAt: TimeInterval?

    public init(duration: TimeInterval = 0.9, jitterTolerance: CGFloat = 18) {
        self.duration = max(duration, 0.15)
        self.jitterTolerance = max(jitterTolerance, 2)
    }

    public mutating func reset() {
        targetID = nil
        origin = nil
        startedAt = nil
    }

    public mutating func update(
        targetID newTargetID: UUID?,
        pointer: CGPoint,
        now: TimeInterval
    ) -> DwellProgress {
        guard let newTargetID else {
            reset()
            return DwellProgress(targetID: nil, progress: 0, completed: false, paused: false)
        }

        if targetID != newTargetID || origin == nil || startedAt == nil {
            targetID = newTargetID
            origin = pointer
            startedAt = now
            return DwellProgress(targetID: newTargetID, progress: 0, completed: false, paused: false)
        }

        guard let origin, let startedAt else {
            return DwellProgress(targetID: newTargetID, progress: 0, completed: false, paused: false)
        }

        let movement = hypot(pointer.x - origin.x, pointer.y - origin.y)
        if movement > jitterTolerance {
            self.origin = pointer
            self.startedAt = now
            return DwellProgress(targetID: newTargetID, progress: 0, completed: false, paused: true)
        }

        let progress = min(max((now - startedAt) / duration, 0), 1)
        return DwellProgress(
            targetID: newTargetID,
            progress: progress,
            completed: progress >= 1,
            paused: false
        )
    }
}
