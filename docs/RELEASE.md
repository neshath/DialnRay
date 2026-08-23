# Release checklist

## Product configuration

- Create a USD 15 yearly Gumroad membership.
- Add a License key block to the Gumroad product content.
- Copy the product ID shown in that block.
- Decide the supported Mac count and enforce it through Gumroad's license-use controls.
- Add final seller identity, support email, refund policy, terms, and privacy copy.

## Apple distribution

- Join the Apple Developer Program.
- Install a Developer ID Application certificate in Keychain.
- Create a `notarytool` Keychain profile.
- Build with the real Gumroad product ID and Developer ID identity.
- Verify the hardened-runtime signature, submit with `notarytool`, staple the ticket, and assess with Gatekeeper.
- Install the DMG on a second clean Mac account before upload.

## Physical acceptance checks

- Permission denial, grant, refresh, and post-grant shortcut behavior.
- Safari, Chrome, Finder, System Settings, Keynote, a design tool, and one custom-canvas app.
- Multiple displays with screens arranged above, below, left, and right.
- Explicit, dwell-confirm, and dwell-auto-click modes.
- Very low and high dwell timing, smoothing, jitter tolerance, and target radius.
- Reduce Motion, Reduce Transparency, Increase Contrast, and keyboard-only cancellation.
- Network offline inside and outside the seven-day license grace period.
- Cancelled, refunded, disputed, and failed Gumroad subscription responses.
- Apple silicon launch, Gatekeeper acceptance, update/reinstall behavior, and permission persistence.
