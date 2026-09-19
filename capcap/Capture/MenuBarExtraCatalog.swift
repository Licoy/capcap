import AppKit
import ApplicationServices

enum MenuBarExtraGeometry {
    static let maxHeight: CGFloat = 64
    static let maxWidth: CGFloat = 400
    static let maxTopInset: CGFloat = 8

    static func isIndividualExtra(
        frame: CGRect,
        displayBounds: [CGRect]
    ) -> Bool {
        guard frame.width > 8,
              frame.height > 8,
              frame.height <= maxHeight,
              frame.width <= maxWidth
        else { return false }

        return displayBounds.contains { display in
            guard display.width > 1, display.height > 1 else { return false }
            let isTopAligned = frame.minY >= display.minY - 1
                && frame.minY <= display.minY + maxTopInset
            let isFullyContained = frame.minX >= display.minX
                && frame.maxX <= display.maxX + 1
                && frame.minY >= display.minY - 1
                && frame.maxY <= display.minY + maxHeight + 1
            let isIndividual = frame.width < display.width * 0.35
                && frame.width <= maxWidth
            return isTopAligned && isFullyContained && isIndividual
        }
    }

    static func uniqued(_ frames: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for frame in frames.sorted(by: { $0.minX < $1.minX }) {
            if let index = result.firstIndex(where: { overlapsSameExtra($0, frame) }) {
                result[index] = preferred(result[index], frame)
            } else {
                result.append(frame)
            }
        }
        return result
    }

    private static func overlapsSameExtra(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        lhs.intersects(rhs.insetBy(dx: -2, dy: -2))
            && abs(lhs.midX - rhs.midX) < 16
    }

    private static func preferred(_ lhs: CGRect, _ rhs: CGRect) -> CGRect {
        if rhs.height > lhs.height { return rhs }
        if lhs.height > rhs.height { return lhs }
        return rhs.width > lhs.width ? rhs : lhs
    }
}

enum MenuBarExtraCatalog {
    static func frames(displayBounds: [CGRect]) -> [CGRect] {
        guard AXIsProcessTrusted() else { return [] }
        guard let pid = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.MenuBarAgent"
        })?.processIdentifier else { return [] }

        var collected: [CGRect] = []
        collectFrames(from: AXUIElementCreateApplication(pid), depth: 0, into: &collected)
        let filtered = collected.filter {
            MenuBarExtraGeometry.isIndividualExtra(frame: $0, displayBounds: displayBounds)
        }
        return MenuBarExtraGeometry.uniqued(filtered)
    }

    private static func collectFrames(
        from element: AXUIElement,
        depth: Int,
        into frames: inout [CGRect]
    ) {
        if let frame = copyFrame(element) {
            frames.append(frame)
        }
        guard depth < 4, copyRole(element) != "AXMenu" else { return }
        for child in copyChildren(element) {
            collectFrames(from: child, depth: depth + 1, into: &frames)
        }
    }

    private static func copyFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
              AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
              ) == .success,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &dimensions)
        let frame = CGRect(origin: origin, size: dimensions)
        guard frame.width > 1, frame.height > 1 else { return nil }
        return frame
    }

    private static func copyRole(_ element: AXUIElement) -> String {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success else { return "" }
        return value as? String ?? ""
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
