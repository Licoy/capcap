import SwiftUI
import AppKit

/// SwiftUI preview of the idle magnifier color picker used in
/// Settings → General. The right-hand side hosts the **real**
/// `IdleColorLensView` (via `NSViewRepresentable`) so the preview
/// reflects the production panel's rendering path; the left-hand
/// side is capcap's real AppIcon loaded from the bundle. No
/// hand-drawn mock shapes — the only AppKit drawing here is the
/// backdrop, everything else is the genuine production code.
struct IdleLensPreviewView: View {

    let iconImage: NSImage
    let mockSnapshot: CGImage
    let mockSample: IdleColorLensWindow.Sample
    let lensSize: CGSize

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            // Capcap logo (the "subject" being magnified).
            Image(nsImage: iconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 17))

            // The real lens view, hosted via NSViewRepresentable.
            LensRepresentable(
                snapshot: mockSnapshot,
                sample: mockSample
            )
            .frame(width: lensSize.width, height: lensSize.height)
        }
        .padding(16)
        .frame(width: requiredWidth, height: requiredHeight)
        .background(Color(NSColor(calibratedWhite: 0.18, alpha: 0.4)))
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

    private var requiredWidth: CGFloat { Self.requiredSize().width }
    private var requiredHeight: CGFloat { Self.requiredSize().height }
}

/// `NSViewRepresentable` adapter for `IdleColorLensView`. Keeps the
/// lens's own drawing pipeline (magnified area, crosshair, coords,
/// HEX, hint rows) so the preview always matches the live panel.
private struct LensRepresentable: NSViewRepresentable {
    let snapshot: CGImage
    let sample: IdleColorLensWindow.Sample

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
    }
}