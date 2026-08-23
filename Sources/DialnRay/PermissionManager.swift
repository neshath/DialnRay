import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    private var monitoringTask: Task<Void, Never>?

    func refresh() {
        accessibilityTrusted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        monitorPermissionChanges()
    }

    func openAccessibilitySettings() {
        requestAccessibility()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func requestScreenRecording() {
        screenRecordingGranted = CGRequestScreenCaptureAccess()
        monitorPermissionChanges()
    }

    func monitorPermissionChanges() {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
                if self.accessibilityTrusted && self.screenRecordingGranted { return }
            }
        }
    }
}
