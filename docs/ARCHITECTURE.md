# DialnRay architecture

## Runtime flow

1. The global input monitor receives Option–Space and anchors the focus dial at the current pointer position.
2. `AdaptiveScanner` captures the frontmost app, bundle identifier, focused window, and locally learned scan profile.
3. `AccessibilityScanner` traverses a bounded portion of the focused window's AX hierarchy and extracts actionable roles, supported actions, labels, and bounds.
4. When explicit targets are sparse, low-confidence layout candidates are derived from nearby exposed labels.
5. If enabled, permitted, and still needed, `VisionScanner` captures only the active app window through ScreenCaptureKit and recognizes local text regions. No captured pixels are persisted or uploaded.
6. Targets are deduplicated, limited by radius, and ranked by pointer direction, distance, confidence, and scan-source reliability.
7. `PointerFilter` smooths movement. `DwellEngine` enforces the configured jitter radius and resets its timer when movement exceeds tolerance.
8. `TargetActivator` attempts the target's AX Press action and falls back to a synthetic click at the recognized center.

## Trust boundaries

- Accessibility metadata and screen pixels stay in memory on the Mac.
- App scan profiles contain only bundle identifiers, source success/failure counts, target counts, and timestamps.
- Gumroad receives the configured product ID and entered license key over HTTPS.
- The license key is stored in the user's Keychain; only verification time and purchase email are cached in UserDefaults.

## Cross-platform path

The platform-independent models, directional ranker, pointer filter, dwell engine, app-profile policy, and license response models live in `DialnRayCore`. A Windows port can map UI Automation targets into `TargetCandidate`; Linux can use AT-SPI. Each platform still needs its own trusted global-input, overlay, permission, visual-capture, and activation adapters.
