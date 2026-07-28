import SwiftUI
import AppKit

/// SwiftUI preview of the idle magnifier color picker used in
/// Settings → General. The right-hand side hosts the **real**
/// `IdleColorLensView` (via `NSViewRepresentable`) so the preview
/// reflects the production panel's rendering path; the left-hand
/// side is capcap's real AppIcon loaded from the bundle. Hover over
/// the icon to drive the lens with real-time pixel sampling.
struct IdleLensPreviewView: View {

    let iconImage: NSImage
    let mockSnapshot: CGImage

    /// Hover location mapped to CGImage pixel coordinates, or `nil`
    /// when the cursor is outside the icon area.
    @State private var hoverLocation: CGPoint? = nil

    /// Bumped on every `UserDefaults.didChangeNotification` so SwiftUI
    /// re-evaluates the body — and therefore re-runs `updateNSView`
    /// on the `LensRepresentable` below.
    @State private var changeToken = 0

    var body: some View {
        // Re-read the live settings on every body evaluation so the
        // lens (and the right-hand panel size) follow user changes.
        let magnifiedSize = Defaults.idleLensMagnifiedSize
        let showCopyHint = Defaults.idleLensShowCopyHint
        let showShiftHint = Defaults.idleLensShowShiftHint
        let lensSize = IdleColorLensWindow.panelSizeForCurrentSettings()
        let iconPt = 76.0
        let scaleX = CGFloat(mockSnapshot.width) / iconPt
        let scaleY = CGFloat(mockSnapshot.height) / iconPt

        return HStack(alignment: .center, spacing: 18) {
            // Capcap logo — the "subject" being magnified.
            // A fake cursor sits on top when idle so the preview
            // never looks empty; it hides during real hover.
            ZStack {
                Image(nsImage: iconImage)
                    .resizable()
                    .frame(width: iconPt, height: iconPt)
                    .clipShape(RoundedRectangle(cornerRadius: 17))

                // Fake cursor — hidden when the real mouse is hovering.
                if hoverLocation == nil {
                    let cursorImg = NSCursor.arrow.image
                    Image(nsImage: cursorImg)
                        .resizable()
                        .frame(width: 22, height: 22)
                        .offset(x: 7, y: 8)
                        .shadow(radius: 2)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    // location is in the ZStack's coordinate space
                    // (0 … 76). Clamp and map to CGImage pixels.
                    let cx = min(max(0, location.x), iconPt)
                    let cy = min(max(0, location.y), iconPt)
                    hoverLocation = CGPoint(x: cx * scaleX, y: cy * scaleY)
                case .ended:
                    hoverLocation = nil
                }
            }

            // The real lens view, hosted via NSViewRepresentable.
            LensRepresentable(
                snapshot: mockSnapshot,
                hoverLocation: hoverLocation,
                showCopyHint: showCopyHint,
                showShiftHint: showShiftHint,
                magnifiedSize: magnifiedSize,
                changeToken: changeToken
            )
            .frame(width: lensSize.width, height: lensSize.height)
        }
        .padding(16)
        .frame(width: requiredWidth(lensSize: lensSize),
               height: requiredHeight(lensSize: lensSize))
        .background(Color(NSColor(calibratedWhite: 0.18, alpha: 0.4)))
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
        ) { _ in
            // Any Defaults change → invalidate SwiftUI so the lens
            // and the surrounding layout re-render.
            changeToken &+= 1
        }
    }

    /// Total preview size. SettingsView uses this to size the
    /// `NSHostingView` it embeds in the card layout.
    static func requiredSize() -> NSSize {
        let lens = IdleColorLensWindow.panelSizeForCurrentSettings()
        return NSSize(
            width: 16 * 2 + 76 + 18 + lens.width,
            height: 16 * 2 + max(76, lens.height)
        )
    }

    private func requiredWidth(lensSize: NSSize) -> CGFloat {
        16 * 2 + 76 + 18 + lensSize.width
    }
    private func requiredHeight(lensSize: NSSize) -> CGFloat {
        16 * 2 + max(76, lensSize.height)
    }
}

/// `NSViewRepresentable` adapter for `IdleColorLensView`. Keeps the
/// lens's own drawing pipeline (magnified area, crosshair, coords,
/// HEX, hint rows) so the preview always matches the live panel.
/// When the user hovers over the icon, the lens samples the pixel
/// under the cursor in real time; otherwise it falls back to the
/// snapshot centre.
private struct LensRepresentable: NSViewRepresentable {
    let snapshot: CGImage
    let hoverLocation: CGPoint?
    let showCopyHint: Bool
    let showShiftHint: Bool
    let magnifiedSize: Int
    /// Dummy token bumped on every `UserDefaults` change. Forces
    /// `updateNSView` to run even when the other properties stay
    /// identical (e.g. background colour changes). Without this,
    /// SwiftUI skips the update and the lens never redraws.
    let changeToken: Int

    func makeNSView(context: Context) -> IdleColorLensView {
        IdleColorLensView(frame: .zero)
    }

    func updateNSView(_ nsView: IdleColorLensView, context: Context) {
        let w = CGFloat(snapshot.width)
        let h = CGFloat(snapshot.height)
        let screenFrame = NSRect(x: 0, y: 0, width: w, height: h)

        // Use the hover-driven pixel coordinate when available;
        // otherwise default to the snapshot centre.
        let pixelPoint: CGPoint
        let mouseLocation: NSPoint
        if let hl = hoverLocation {
            pixelPoint = hl
            // Convert CGImage y-down → AppKit y-up for Points display.
            mouseLocation = NSPoint(x: hl.x, y: h - hl.y)
        } else {
            let cx = w / 2
            let cy = h / 2
            pixelPoint = CGPoint(x: cx, y: cy)
            mouseLocation = NSPoint(x: cx, y: h - cy)
        }

        let sample = IdleColorLensSampler.sample(image: snapshot, at: pixelPoint)
            ?? IdleColorLensWindow.Sample(r: 0, g: 0, b: 0)

        nsView.format = .hex
        nsView.update(
            sample: sample,
            pixelPoint: pixelPoint,
            mouseLocation: mouseLocation,
            snapshot: snapshot,
            screenFrame: screenFrame,
            format: .hex
        )
        // Re-feed after the magnified size changes so the panel frame
        // matches what the user just picked in Settings.
        let newSize = IdleColorLensWindow.panelSizeForCurrentSettings()
        if nsView.frame.size != newSize {
            nsView.frame = NSRect(origin: nsView.frame.origin, size: newSize)
        }
        // Always mark dirty so changes to background colour, follow-
        // system-appearance, and other Defaults that don't affect the
        // Representable's own properties still trigger a redraw.
        nsView.needsDisplay = true
    }
}