import AppKit
import Combine
import DialnRayCore
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let activationMode = "activationMode"
        static let dwellDuration = "dwellDuration"
        static let jitterTolerance = "jitterTolerance"
        static let smoothing = "smoothing"
        static let targetRadius = "targetRadius"
        static let maximumTargets = "maximumTargets"
        static let visionFallback = "visionFallback"
        static let diagnosticsVisible = "diagnosticsVisible"
        static let rayIntensity = "rayIntensity"
        static let firstLaunchComplete = "firstLaunchComplete"
    }

    private let defaults: UserDefaults

    @Published var activationMode: ActivationMode { didSet { defaults.set(activationMode.rawValue, forKey: Key.activationMode) } }
    @Published var dwellDuration: Double { didSet { defaults.set(dwellDuration, forKey: Key.dwellDuration) } }
    @Published var jitterTolerance: Double { didSet { defaults.set(jitterTolerance, forKey: Key.jitterTolerance) } }
    @Published var smoothing: Double { didSet { defaults.set(smoothing, forKey: Key.smoothing) } }
    @Published var targetRadius: Double { didSet { defaults.set(targetRadius, forKey: Key.targetRadius) } }
    @Published var maximumTargets: Int { didSet { defaults.set(maximumTargets, forKey: Key.maximumTargets) } }
    @Published var visionFallback: Bool { didSet { defaults.set(visionFallback, forKey: Key.visionFallback) } }
    @Published var diagnosticsVisible: Bool { didSet { defaults.set(diagnosticsVisible, forKey: Key.diagnosticsVisible) } }
    @Published var rayIntensity: Double { didSet { defaults.set(rayIntensity, forKey: Key.rayIntensity) } }
    @Published var firstLaunchComplete: Bool { didSet { defaults.set(firstLaunchComplete, forKey: Key.firstLaunchComplete) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activationMode = ActivationMode(rawValue: defaults.string(forKey: Key.activationMode) ?? "") ?? .dwellConfirm
        dwellDuration = defaults.object(forKey: Key.dwellDuration) as? Double ?? 0.9
        jitterTolerance = defaults.object(forKey: Key.jitterTolerance) as? Double ?? 18
        smoothing = defaults.object(forKey: Key.smoothing) as? Double ?? 0.72
        targetRadius = defaults.object(forKey: Key.targetRadius) as? Double ?? 760
        maximumTargets = defaults.object(forKey: Key.maximumTargets) as? Int ?? 8
        visionFallback = defaults.object(forKey: Key.visionFallback) as? Bool ?? true
        diagnosticsVisible = defaults.object(forKey: Key.diagnosticsVisible) as? Bool ?? true
        rayIntensity = defaults.object(forKey: Key.rayIntensity) as? Double ?? 0.72
        firstLaunchComplete = defaults.bool(forKey: Key.firstLaunchComplete)
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
}
