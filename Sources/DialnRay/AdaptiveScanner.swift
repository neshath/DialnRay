import AppKit
import DialnRayCore
import Foundation

struct AdaptiveScanResult {
    var summary: ScanSummary
    var discoveredTargets: [DiscoveredTarget]
}

@MainActor
final class AdaptiveScanner {
    private let accessibilityScanner = AccessibilityScanner()
    private let visionScanner = VisionScanner()
    private let profileStore: AppProfileStore

    init(profileStore: AppProfileStore = AppProfileStore()) {
        self.profileStore = profileStore
    }

    func scan(cursor: CGPoint, settings: SettingsStore) async -> AdaptiveScanResult? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }

        let started = CFAbsoluteTimeGetCurrent()
        let accessibility = accessibilityScanner.scan(frontmostApp: app, cursor: cursor)
        var discovered = accessibility.targets
        var sources: [ScanSource] = []
        var profile = profileStore.profile(for: accessibility.app.bundleIdentifier)

        if !accessibility.targets.isEmpty {
            sources.append(.accessibility)
        }
        profile.record(source: .accessibility, targetCount: accessibility.targets.count)

        if accessibility.targets.count < 10 {
            let layoutTargets = accessibility.staticTextTargets.filter { predicted in
                !discovered.contains { existing in existing.candidate.frame.intersects(predicted.candidate.frame) }
            }
            if !layoutTargets.isEmpty {
                discovered.append(contentsOf: layoutTargets)
                sources.append(.layout)
            }
            profile.record(source: .layout, targetCount: layoutTargets.count)
        }

        var degradedReason: String?
        if settings.visionFallback, accessibility.targets.count < 6 {
            if CGPreflightScreenCaptureAccess() {
                do {
                    let visionTargets = try await visionScanner.scan(app: accessibility.app)
                        .filter { vision in
                            !discovered.contains { existing in
                                existing.candidate.frame.intersects(vision.candidate.frame)
                            }
                        }
                    if !visionTargets.isEmpty {
                        discovered.append(contentsOf: visionTargets)
                        sources.append(.vision)
                    }
                    profile.record(source: .vision, targetCount: visionTargets.count)
                } catch {
                    degradedReason = "Visual recognition was unavailable. Accessibility targets are still active."
                    profile.record(source: .vision, targetCount: 0)
                }
            } else {
                degradedReason = "Screen Recording is off, so custom-drawn controls may be missed."
            }
        }

        let radius = settings.targetRadius
        discovered = discovered.filter {
            hypot($0.candidate.center.x - cursor.x, $0.candidate.center.y - cursor.y) <= radius
        }
        profileStore.save(profile)

        let summary = ScanSummary(
            app: accessibility.app,
            sources: sources,
            targets: discovered.map(\.candidate),
            duration: CFAbsoluteTimeGetCurrent() - started,
            degradedReason: degradedReason
        )
        return AdaptiveScanResult(summary: summary, discoveredTargets: discovered)
    }
}
