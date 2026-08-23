import Foundation

public struct AppScanProfile: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var preferredSources: [ScanSource]
    public var successfulScans: [ScanSource: Int]
    public var failedScans: [ScanSource: Int]
    public var lastTargetCount: Int
    public var lastUpdated: Date

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
        self.preferredSources = [.accessibility, .layout, .vision]
        self.successfulScans = [:]
        self.failedScans = [:]
        self.lastTargetCount = 0
        self.lastUpdated = .distantPast
    }

    public mutating func record(source: ScanSource, targetCount: Int) {
        if targetCount > 0 {
            successfulScans[source, default: 0] += 1
        } else {
            failedScans[source, default: 0] += 1
        }
        lastTargetCount = targetCount
        lastUpdated = Date()
        let sourceScores = Dictionary(uniqueKeysWithValues: preferredSources.map { ($0, score(for: $0)) })
        preferredSources.sort { sourceScores[$0, default: 0] > sourceScores[$1, default: 0] }
    }

    public func score(for source: ScanSource) -> Double {
        let success = Double(successfulScans[source, default: 0])
        let failure = Double(failedScans[source, default: 0])
        return (success + 1) / (success + failure + 2)
    }
}

public final class AppProfileStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "DialnRay.AppScanProfiles.v1"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func profile(for bundleIdentifier: String) -> AppScanProfile {
        lock.lock()
        defer { lock.unlock() }
        return readProfiles()[bundleIdentifier] ?? AppScanProfile(bundleIdentifier: bundleIdentifier)
    }

    public func save(_ profile: AppScanProfile) {
        lock.lock()
        defer { lock.unlock() }
        var profiles = readProfiles()
        profiles[profile.bundleIdentifier] = profile
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }

    private func readProfiles() -> [String: AppScanProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([String: AppScanProfile].self, from: data) else {
            return [:]
        }
        return profiles
    }
}
