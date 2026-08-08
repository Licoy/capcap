import AppKit
import CoreGraphics

/// Persisted geometry of the most recent screen selection so the user can
/// reopen capture with the same region pre-filled.
struct LastCaptureRegion: Codable, Equatable {
    var displayID: UInt32
    var screenRectX: Double
    var screenRectY: Double
    var screenRectWidth: Double
    var screenRectHeight: Double
    var captureRectX: Double
    var captureRectY: Double
    var captureRectWidth: Double
    var captureRectHeight: Double
    var isWindowCapture: Bool
    var windowID: UInt32?
    var updatedAt: Date

    var screenRect: NSRect {
        NSRect(
            x: screenRectX,
            y: screenRectY,
            width: screenRectWidth,
            height: screenRectHeight
        )
    }

    var captureRect: CGRect {
        CGRect(
            x: captureRectX,
            y: captureRectY,
            width: captureRectWidth,
            height: captureRectHeight
        )
    }

    init(
        displayID: CGDirectDisplayID,
        screenRect: NSRect,
        captureRect: CGRect,
        isWindowCapture: Bool,
        windowID: CGWindowID?,
        updatedAt: Date = Date()
    ) {
        self.displayID = displayID
        self.screenRectX = Double(screenRect.origin.x)
        self.screenRectY = Double(screenRect.origin.y)
        self.screenRectWidth = Double(screenRect.width)
        self.screenRectHeight = Double(screenRect.height)
        self.captureRectX = Double(captureRect.origin.x)
        self.captureRectY = Double(captureRect.origin.y)
        self.captureRectWidth = Double(captureRect.width)
        self.captureRectHeight = Double(captureRect.height)
        self.isWindowCapture = isWindowCapture
        self.windowID = windowID.map { UInt32($0) }
        self.updatedAt = updatedAt
    }

    /// Resolves a usable AppKit screen rect for the current display layout.
    /// Clamps to the original display when it still exists; otherwise clamps
    /// onto the screen under the mouse (or main screen).
    func resolvedScreenRect(didRelocate: inout Bool) -> (screen: NSScreen, rect: NSRect)? {
        didRelocate = false
        let original = screenRect
        guard original.width >= 5, original.height >= 5 else { return nil }

        if let match = NSScreen.screens.first(where: { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return id == CGDirectDisplayID(displayID)
        }) {
            let clamped = Self.clamp(original, to: match.frame)
            if clamped != original { didRelocate = true }
            guard clamped.width >= 5, clamped.height >= 5 else { return nil }
            return (match, clamped)
        }

        didRelocate = true
        let fallback = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = fallback else { return nil }
        var rect = original
        // Preserve size; move origin onto the fallback screen centered if needed.
        if rect.width > screen.frame.width {
            rect.size.width = screen.frame.width
        }
        if rect.height > screen.frame.height {
            rect.size.height = screen.frame.height
        }
        rect.origin.x = screen.frame.midX - rect.width / 2
        rect.origin.y = screen.frame.midY - rect.height / 2
        rect = Self.clamp(rect, to: screen.frame)
        guard rect.width >= 5, rect.height >= 5 else { return nil }
        return (screen, rect)
    }

    private static func clamp(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        var result = rect
        if result.width > bounds.width { result.size.width = bounds.width }
        if result.height > bounds.height { result.size.height = bounds.height }
        result.origin.x = min(max(result.origin.x, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.origin.y, bounds.minY), bounds.maxY - result.height)
        return result
    }
}
