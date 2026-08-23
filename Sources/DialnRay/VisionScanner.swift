import AppKit
import DialnRayCore
import ScreenCaptureKit
import Vision

@available(macOS 14.0, *)
final class VisionScanner {
    func scan(app: AppContext) async throws -> [DiscoveredTarget] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = bestWindow(in: content.windows, app: app) else { return [] }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width * 1.5), 1)
        configuration.height = max(Int(window.frame.height * 1.5), 1)
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.014
        try VNImageRequestHandler(cgImage: image).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  text.count <= 80 else { return nil }

            let box = observation.boundingBox
            let quartzFrame = CGRect(
                x: window.frame.minX + box.minX * window.frame.width - 8,
                y: window.frame.minY + (1 - box.maxY) * window.frame.height - 7,
                width: box.width * window.frame.width + 16,
                height: box.height * window.frame.height + 14
            )
            let frame = ScreenGeometry.appKitRectFromAX(quartzFrame)
            guard frame.width >= 20, frame.height >= 16, frame.width <= 420 else { return nil }
            let candidate = TargetCandidate(
                label: text,
                role: "Recognized control",
                frame: frame,
                source: .vision,
                confidence: Double(observation.confidence) * 0.72,
                action: .click
            )
            return DiscoveredTarget(candidate: candidate)
        }
    }

    private func bestWindow(in windows: [SCWindow], app: AppContext) -> SCWindow? {
        windows
            .filter { $0.owningApplication?.processID == app.processIdentifier && $0.isOnScreen }
            .max { lhs, rhs in
                let lhsTitleBoost = lhs.title == app.windowTitle ? 1_000_000.0 : 0
                let rhsTitleBoost = rhs.title == app.windowTitle ? 1_000_000.0 : 0
                return lhs.frame.width * lhs.frame.height + lhsTitleBoost
                    < rhs.frame.width * rhs.frame.height + rhsTitleBoost
            }
    }
}
