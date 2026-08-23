import CoreGraphics
import Foundation

public enum ScanSource: String, Codable, CaseIterable, Sendable {
    case accessibility = "Accessibility"
    case layout = "Layout"
    case vision = "Vision"
}

public enum TargetAction: String, Codable, Sendable {
    case press
    case click
    case focus
}

public struct TargetCandidate: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var label: String
    public var role: String
    public var frame: CGRect
    public var source: ScanSource
    public var confidence: Double
    public var action: TargetAction

    public init(
        id: UUID = UUID(),
        label: String,
        role: String,
        frame: CGRect,
        source: ScanSource,
        confidence: Double,
        action: TargetAction = .press
    ) {
        self.id = id
        self.label = label
        self.role = role
        self.frame = frame
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.action = action
    }

    public var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

public struct AppContext: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String
    public var processIdentifier: Int32
    public var windowTitle: String?
    public var windowFrame: CGRect?

    public init(
        bundleIdentifier: String,
        displayName: String,
        processIdentifier: Int32,
        windowTitle: String? = nil,
        windowFrame: CGRect? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.processIdentifier = processIdentifier
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
    }
}

public struct ScanSummary: Equatable, Sendable {
    public var app: AppContext
    public var sources: [ScanSource]
    public var targets: [TargetCandidate]
    public var duration: TimeInterval
    public var degradedReason: String?

    public init(
        app: AppContext,
        sources: [ScanSource],
        targets: [TargetCandidate],
        duration: TimeInterval,
        degradedReason: String? = nil
    ) {
        self.app = app
        self.sources = sources
        self.targets = targets
        self.duration = duration
        self.degradedReason = degradedReason
    }
}

public enum ActivationMode: String, Codable, CaseIterable, Sendable {
    case explicit = "Explicit confirmation"
    case dwellConfirm = "Dwell confirmation"
    case dwellAutoClick = "Dwell auto-click"
}

public enum InteractionPhase: Equatable, Sendable {
    case idle
    case scanning
    case tracking
    case selected(UUID)
    case latched(UUID, progress: Double)
    case activated(UUID)
    case failed(String)
}
