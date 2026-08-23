import AppKit

enum DialnRayTheme {
    static let background = NSColor(calibratedWhite: 0.035, alpha: 0.52)
    static let surface = NSColor(calibratedRed: 0.075, green: 0.092, blue: 0.082, alpha: 0.94)
    static let surfaceRaised = NSColor(calibratedRed: 0.105, green: 0.125, blue: 0.112, alpha: 0.97)
    static let ink = NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.93, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.64, alpha: 1)
    static let ready = NSColor(calibratedRed: 0.31, green: 0.58, blue: 0.24, alpha: 1)
    static let target = NSColor(calibratedRed: 0.24, green: 0.80, blue: 0.93, alpha: 1)
    static let selectedRay = NSColor(calibratedRed: 0.96, green: 0.16, blue: 0.14, alpha: 1)
    static let warning = NSColor(calibratedRed: 0.96, green: 0.67, blue: 0.16, alpha: 1)
    static let error = NSColor(calibratedRed: 0.95, green: 0.29, blue: 0.18, alpha: 1)
    static let hairline = NSColor(calibratedWhite: 1, alpha: 0.14)

    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func monospacedDigits(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}
