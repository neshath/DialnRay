# DialnRay

DialnRay is a native macOS motor-accessibility utility that makes dense interfaces easier to reach. Press **Option–Space**, move around the dial toward a recognized control, hold to latch, and confirm or auto-click using the configured activation mode.

## What the Mac v1 includes

- Frontmost app and focused-window recognition.
- Accessibility hierarchy scanning for roles, labels, actions, and bounds.
- App-specific local scan profiles that prioritize successful recognition sources.
- Geometric predictions from exposed layout text when explicit actions are sparse.
- Opt-in Screen Recording and Vision recognition for custom-rendered interfaces.
- Directional target ranking, smoothing, jitter tolerance, dwell timing, and cancellation.
- Native AX press activation with a pointer-click fallback.
- Focus Field overlay with a compact diagnostics rail.
- Native Settings, permission onboarding, Keychain storage, and Gumroad annual-license verification.
- Release bundling, Developer ID signing, hardened runtime, and notarization scripts.

## Requirements

- macOS 14 or later.
- Accessibility permission for global input, scanning, and control activation.
- Screen Recording permission only if visual recognition is enabled.
- Xcode 16 or later to build. The current project is verified with Swift 6.2/Xcode 26.

## Build and test

```sh
swift test
CONFIGURATION=debug ./scripts/build-app.sh
open build/DialnRay.app
```

Debug builds allow local interaction testing without a Gumroad product ID. Release builds always require a verified license.

## Gumroad setup

Create DialnRay as a yearly membership priced at USD 15, add Gumroad's License key block to the product content, and copy the displayed product ID. Product IDs—not permalinks—are required by Gumroad for products created on or after January 9, 2023.

```sh
GUMROAD_PRODUCT_ID='your-product-id' \
CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='dialnray-notary' \
./scripts/notarize-release.sh
```

Routine launch checks send `increment_uses_count=false`. The first activation increments uses once. Refunded, disputed, chargebacked, ended, cancelled, and failed subscriptions are rejected. A successful verification grants seven days of offline use.

## Evidence boundary

The source and automated tests can validate scanner policy, ranking, dwell safety, licensing state, compilation, and bundle construction. They cannot prove that every third-party app exposes useful Accessibility metadata, that Screen Recording permission has been granted, or that physical dwell interaction suits a particular person's motor response. Test those paths on supported Macs before selling the build.
