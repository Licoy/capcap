import SwiftUI
import AppKit

/// SwiftUI preview of the idle magnifier color picker used in
/// Settings → General. The right-hand side hosts the **real**
/// `IdleColorLensView` (via `NSViewRepresentable`) so the preview
/// reflects the production panel's rendering path; the left-hand
/// side is capcap's real AppIcon loaded from the bundle. Reacts
/// live to `UserDefaults` changes — any setting toggle repaints
/// the lens and the surrounding layout.
struct IdleLensPreviewView: View {

    let iconImage: NSImage
    let mockSnapshot: CGImage
    let mockSample: IdleColorLensWindow.Sample

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

        return HStack(alignment: .center, spacing: 18) {
            // Capcap logo (the "subject" being magnified) with a
            // macOS arrow cursor overlaid so the preview looks like
            // a real cursor is hovering over the icon.
            ZStack {
                Image(nsImage: iconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 17))

                let cursorImg = NSCursor.arrow.image
                Image(nsImage: cursorImg)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .offset(x: 7, y: 8)
                    .shadow(radius: 2)
            }

            // The real lens view, hosted via NSViewRepresentable.
            LensRepresentable(
                snapshot: mockSnapshot,
                sample: mockSample,
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
private struct LensRepresentable: NSViewRepresentable {
    let snapshot: CGImage
    let sample: IdleColorLensWindow.Sample
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
        let screenFrame = NSRect(
            x: 0, y: 0,
            width: snapshot.width,
            height: snapshot.height
        )
        // Sample the centre pixel of the mock icon so the lens shows the
        // subject's dominant colour as HEX.
        let center = CGPoint(
            x: snapshot.width / 2,
            y: snapshot.height / 2
        )
        // Mock mouse position so the lens shows realistic coordinates.
        let mouseLocation = NSPoint(x: 189, y: 762)
        nsView.format = .hex
        nsView.update(
            sample: sample,
            pixelPoint: center,
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