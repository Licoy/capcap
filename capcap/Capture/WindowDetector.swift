import AppKit
import CoreGraphics

enum DetectedWindowTarget: Equatable, Sendable {
    case applicationWindow
    case menuBarComponent
    case elevatedWindow
}

struct WindowDetectionContext: Sendable {
    let primaryScreenArea: CGFloat
    let displayBounds: [CGRect]
    var menuBarExtras: [CGRect] = []
}

struct DetectedWindow: Sendable {
    private static let elevatedLayers: Set<Int> = [
        Int(CGWindowLevelForKey(.floatingWindow)),
        Int(CGWindowLevelForKey(.modalPanelWindow)),
        Int(CGWindowLevelForKey(.utilityWindow)),
        Int(CGWindowLevelForKey(.popUpMenuWindow))
    ]

    let name: String
    let windowID: CGWindowID
    let layer: Int
    let frame: CGRect   // CG coordinates (global, top-left origin)
    let target: DetectedWindowTarget

    var usesCompositedScreenBackdrop: Bool {
        target == .menuBarComponent || layer >= 20
    }

    static var selectableElevatedLayers: Set<Int> { elevatedLayers }
}

enum WindowDetectionError: LocalizedError, Sendable {
    case invalidPrimaryScreenArea(CGFloat)
    case windowListUnavailable
    case invalidWindowListPayload

    var errorDescription: String? {
        switch self {
        case .invalidPrimaryScreenArea(let area):
            return "Invalid primary screen area for window detection: \(area)"
        case .windowListUnavailable:
            return "Core Graphics did not return a window list"
        case .invalidWindowListPayload:
            return "Core Graphics returned an unexpected window list payload"
        }
    }
}

class WindowDetector {
    private var windows: [DetectedWindow] = []

    /// Build an immutable window snapshot without touching AppKit screen state
    /// or this detector's mutable state. Safe to call from a background queue.
    static func snapshot(
        context: WindowDetectionContext
    ) -> Result<[DetectedWindow], WindowDetectionError> {
        guard context.primaryScreenArea.isFinite, context.primaryScreenArea > 0 else {
            return .failure(.invalidPrimaryScreenArea(context.primaryScreenArea))
        }

        guard let rawInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) else {
            return .failure(.windowListUnavailable)
        }
        guard let infoList = rawInfoList as? [[String: Any]] else {
            return .failure(.invalidWindowListPayload)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        let detectedWindows: [DetectedWindow] = infoList.compactMap { info -> DetectedWindow? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsNS = info[kCGWindowBounds as String] as? NSDictionary,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= 0
            else { return nil }

            // Keep this app's own menus/popups detectable so capcap can capture
            // its visible transient UI. Only screen-saver-level chrome (toasts,
            // tooltips, countdown and progress panels) is excluded.
            // The capture overlay itself is created after refresh(), so it is
            // never in this snapshot.
            if pid == ownPID && layer >= Int(CGWindowLevelForKey(.screenSaverWindow)) {
                return nil
            }

            // Skip fully transparent windows (invisible system overlays)
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                return nil
            }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsNS as CFDictionary, &rect) else { return nil }
            guard rect.width > 1, rect.height > 1 else { return nil }
            guard let target = targetType(
                layer: layer,
                frame: rect,
                displayBounds: context.displayBounds
            ) else { return nil }

            // High-layer system overlays that fill most of the screen are
            // typically invisible IME/backdrop surfaces, not capture targets.
            if target == .elevatedWindow,
               rect.width * rect.height > context.primaryScreenArea * 0.8 {
                return nil
            }

            let name = info[kCGWindowOwnerName as String] as? String ?? ""
            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            return DetectedWindow(
                name: name,
                windowID: windowID,
                layer: layer,
                frame: rect,
                target: target
            )
        }

        return .success(mergingMenuBarExtras(context.menuBarExtras, into: detectedWindows))
    }

    static func mergingMenuBarExtras(
        _ extras: [CGRect],
        into windows: [DetectedWindow]
    ) -> [DetectedWindow] {
        let extraWindows = extras.enumerated().map { index, frame in
            DetectedWindow(
                name: "Menu Extra",
                windowID: syntheticMenuBarExtraWindowID(index: index, frame: frame),
                layer: Int(CGWindowLevelForKey(.statusWindow)),
                frame: frame,
                target: .menuBarComponent
            )
        }
        return extraWindows + windows
    }

    private static func syntheticMenuBarExtraWindowID(index: Int, frame: CGRect) -> CGWindowID {
        var hasher = Hasher()
        hasher.combine(index)
        hasher.combine(Int(frame.minX.rounded()))
        hasher.combine(Int(frame.minY.rounded()))
        hasher.combine(Int(frame.width.rounded()))
        hasher.combine(Int(frame.height.rounded()))
        let bits = UInt32(truncatingIfNeeded: hasher.finalize())
        return 0xC000_0000 | (bits & 0x3FFF_FFFF)
    }

    /// Classifies only stable capture targets. Layer-0 app windows remain
    /// selectable, along with popup/utility panels. At the status-window
    /// level, accept a single short window aligned to the top of one display,
    /// while rejecting full menu bars, cursors, and other transients.
    static func targetType(
        layer: Int,
        frame: CGRect,
        displayBounds: [CGRect]
    ) -> DetectedWindowTarget? {
        if layer == 0 || layer == Int(CGWindowLevelForKey(.normalWindow)) {
            return .applicationWindow
        }
        if DetectedWindow.selectableElevatedLayers.contains(layer) {
            return .elevatedWindow
        }
        let statusLikeLayers: Set<Int> = [
            Int(CGWindowLevelForKey(.statusWindow)),
            Int(CGWindowLevelForKey(.mainMenuWindow))
        ]
        guard statusLikeLayers.contains(layer),
              MenuBarExtraGeometry.isIndividualExtra(frame: frame, displayBounds: displayBounds)
        else { return nil }
        return .menuBarComponent
    }

    /// Commit a previously-created value snapshot to this detector.
    func apply(_ detectedWindows: [DetectedWindow]) {
        windows = detectedWindows
    }

    /// High-layer system surfaces (menu bar, Dock, popups) are often only a
    /// translucent foreground when captured as independent windows. Capture
    /// their already-composited screen pixels instead.
    func usesCompositedScreenBackdrop(forWindowID windowID: CGWindowID) -> Bool {
        windows.first { $0.windowID == windowID }?.usesCompositedScreenBackdrop ?? false
    }

    /// Return the topmost window whose frame contains `cgPoint`
    /// (CG coordinates: origin at top-left of primary display, y increases downward).
    func windowAt(cgPoint: CGPoint) -> DetectedWindow? {
        // CGWindowListCopyWindowInfo returns windows in front-to-back z-order,
        // so the first hit is the topmost window.
        windows.first { $0.frame.contains(cgPoint) }
    }
}
