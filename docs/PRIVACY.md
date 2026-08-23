# DialnRay privacy behavior

DialnRay is designed for local processing.

- It reads Accessibility metadata from the frontmost application only while the focus field is active.
- If visual recognition is enabled and Accessibility metadata is insufficient, it captures the active app window in memory and processes it with Apple's on-device Vision framework.
- It does not save screenshots, recognized text, application content, or pointer history.
- It does not include analytics, advertising, crash-reporting SDKs, or telemetry.
- Local app profiles store only a bundle identifier, scanner success counts, the last target count, and an update timestamp.
- License activation sends the Gumroad product ID and the license key to Gumroad over HTTPS. The key is stored in macOS Keychain.

Before publication, place the final seller name and support contact in this document and on the Gumroad product page.
