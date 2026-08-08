import AppKit

/// Parses free-form size strings typed during selection (`800x600`, `800×600`,
/// `800 600`).
enum SelectionSizeParser {
    static func parse(_ raw: String) -> (width: CGFloat, height: CGFloat)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "X", with: "x")
            .replacingOccurrences(of: "*", with: "x")
            .replacingOccurrences(of: ",", with: " ")

        let parts: [String]
        if normalized.contains("x") {
            parts = normalized.split(separator: "x", omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        } else {
            parts = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }

        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width.isFinite, height.isFinite,
              width > 0, height > 0
        else {
            return nil
        }

        return (CGFloat(width), CGFloat(height))
    }
}

/// Floating panel for exact selection size + aspect-ratio presets.
/// Sits above the screen-saver-level capture overlay so it stays visible and
/// key for typing.
final class SelectionSizeInputController {
    private var panel: SizeInputPanel?
    private var field: NSTextField?
    private var ratioButtons: [NSButton] = []
    private var selectedRatio: CGFloat?
    private var onApply: ((CGFloat, CGFloat, CGFloat?) -> Void)?
    private var onCancel: (() -> Void)?
    private var localMonitor: Any?
    private var isSubmitting = false

    var isActive: Bool { panel != nil }

    /// - Parameters:
    ///   - aspectRatio: current locked ratio, or `nil` for free.
    ///   - onApply: width, height, and optional aspect ratio to lock.
    ///     Typed width/height are always authoritative; ratio only locks
    ///     subsequent drag-resize behavior.
    func present(
        near screenRect: NSRect,
        initialWidth: CGFloat,
        initialHeight: CGFloat,
        aspectRatio: CGFloat?,
        onApply: @escaping (CGFloat, CGFloat, CGFloat?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss(apply: false)

        self.onApply = onApply
        self.onCancel = onCancel
        self.selectedRatio = aspectRatio
        self.isSubmitting = false

        let panelWidth: CGFloat = 268
        let panelHeight: CGFloat = 96
        let origin = clampedOrigin(
            preferred: NSPoint(x: screenRect.minX, y: screenRect.maxY + 8),
            size: NSSize(width: panelWidth, height: panelHeight),
            near: screenRect
        )
        let frame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight))

        let panel = SizeInputPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Overlay shells use `.screenSaver`; stay strictly above them.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 8)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.sharingType = .none

        let container = SizeInputContainerView(frame: NSRect(origin: .zero, size: frame.size))
        container.onSubmit = { [weak self] in self?.submitCurrent() }
        container.onCancel = { [weak self] in self?.dismiss(apply: false) }

        // Ratio row
        let ratioSpecs: [(label: String, ratio: CGFloat?)] = [
            (L10n.magnifierLensPanelAspectFree, nil),
            ("1:1", 1.0),
            ("4:3", 4.0 / 3.0),
            ("3:2", 3.0 / 2.0),
            ("16:9", 16.0 / 9.0),
            ("9:16", 9.0 / 16.0),
        ]
        var buttons: [NSButton] = []
        let chipY: CGFloat = 58
        let chipH: CGFloat = 26
        var chipX: CGFloat = 10
        for spec in ratioSpecs {
            let title = spec.label
            let btn = NSButton(
                frame: NSRect(x: chipX, y: chipY, width: 40, height: chipH)
            )
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.title = title
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            btn.contentTintColor = .white
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 5
            btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            btn.target = container
            btn.action = #selector(SizeInputContainerView.ratioClicked(_:))
            btn.tag = buttons.count
            // Fit title width
            let textW = (title as NSString).size(withAttributes: [
                .font: btn.font as Any
            ]).width
            let w = max(36, ceil(textW) + 12)
            btn.setFrameSize(NSSize(width: w, height: chipH))
            container.addSubview(btn)
            buttons.append(btn)
            chipX += w + 4
        }
        container.ratioButtons = buttons
        container.ratioValues = ratioSpecs.map(\.ratio)
        container.onRatioSelected = { [weak self, weak container] index in
            guard let self, let container else { return }
            self.selectedRatio = container.ratioValues[index]
            self.syncRatioButtonStyles()
            // Suggest matching height while the user is still editing; submit
            // still reads whatever is in the field as the final size.
            self.syncHeightFromWidthIfNeeded()
        }

        // Size field
        let field = NSTextField(frame: NSRect(x: 10, y: 14, width: panelWidth - 72, height: 28))
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.10)
        field.focusRingType = .none
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        field.textColor = .white
        field.placeholderString = L10n.selectionSizeInputHint
        field.stringValue = "\(Int(initialWidth.rounded()))x\(Int(initialHeight.rounded()))"
        field.delegate = container
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        // Prevent the field's default action from bubbling as a cancel-ish end.
        field.target = container
        field.action = #selector(SizeInputContainerView.submitClicked)
        container.field = field
        container.addSubview(field)

        let ok = NSButton(frame: NSRect(x: panelWidth - 54, y: 14, width: 44, height: 28))
        ok.bezelStyle = .inline
        ok.isBordered = false
        ok.title = "↵"
        ok.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        ok.contentTintColor = .white
        ok.wantsLayer = true
        ok.layer?.cornerRadius = 6
        ok.layer?.backgroundColor = NSColor(red: 0, green: 212.0 / 255.0, blue: 106.0 / 255.0, alpha: 1).cgColor
        ok.target = container
        ok.action = #selector(SizeInputContainerView.submitClicked)
        ok.keyEquivalent = "\r"
        container.addSubview(ok)

        panel.contentView = container
        self.panel = panel
        self.field = field
        self.ratioButtons = buttons
        syncRatioButtonStyles()

        // Must order front after content is attached; use regardless so a
        // non-activating capture shell cannot bury this panel.
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)

        // Installed last so it runs before the overlay's session-level key
        // monitor and can own Escape / Return while the field is open.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53, mods.isEmpty { // Escape
                self.dismiss(apply: false)
                return nil
            }
            if (event.keyCode == 36 || event.keyCode == 76), mods.isEmpty {
                // Return / keypad Enter — always apply, never cancel the session.
                self.submitCurrent()
                return nil
            }
            return event
        }
    }

    func dismiss(apply: Bool) {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        field = nil
        ratioButtons = []
        isSubmitting = false
        if !apply {
            let cancel = onCancel
            onApply = nil
            onCancel = nil
            cancel?()
            return
        }
        onApply = nil
        onCancel = nil
    }

    private func submitCurrent() {
        // Prefer the field editor's live string so an uncommitted IME / typed
        // value is not lost if the control has not yet flushed to stringValue.
        let live = field?.currentEditor()?.string
        let text = live ?? field?.stringValue ?? ""
        submit(text)
    }

    private func submit(_ text: String) {
        guard !isSubmitting else { return }
        guard let parsed = SelectionSizeParser.parse(text) else {
            ToastWindow.show(message: L10n.selectionSizeInputInvalid)
            return
        }
        // Typed W×H is authoritative. Ratio chips only lock later drag-resize;
        // they must not rewrite the dimensions the user just entered.
        isSubmitting = true
        let apply = onApply
        let ratio = selectedRatio
        onApply = nil
        onCancel = nil
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        field = nil
        ratioButtons = []
        isSubmitting = false
        apply?(parsed.width, parsed.height, ratio)
    }

    private func syncRatioButtonStyles() {
        for (index, btn) in ratioButtons.enumerated() {
            let value = (btn.superview as? SizeInputContainerView)?.ratioValues[index]
            let selected: Bool
            if let value, let selectedRatio {
                selected = abs(value - selectedRatio) < 0.000_001
            } else {
                selected = value == nil && selectedRatio == nil
            }
            btn.layer?.backgroundColor = selected
                ? NSColor(red: 0, green: 212.0 / 255.0, blue: 106.0 / 255.0, alpha: 0.85).cgColor
                : NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    private func syncHeightFromWidthIfNeeded() {
        guard let ratio = selectedRatio, ratio > 0,
              let field,
              let parsed = SelectionSizeParser.parse(field.stringValue)
        else { return }
        let h = max(1, (parsed.width / ratio).rounded())
        field.stringValue = "\(Int(parsed.width.rounded()))x\(Int(h))"
    }

    private func clampedOrigin(preferred: NSPoint, size: NSSize, near screenRect: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(screenRect.origin, $0.frame, false) }
            ?? NSScreen.screens.first { $0.frame.intersects(screenRect) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var origin = preferred
        if origin.y + size.height > visible.maxY {
            origin.y = max(visible.minY + 4, screenRect.minY - size.height - 8)
        }
        if origin.y < visible.minY {
            origin.y = visible.minY + 4
        }
        if origin.x + size.width > visible.maxX {
            origin.x = visible.maxX - size.width - 4
        }
        if origin.x < visible.minX {
            origin.x = visible.minX + 4
        }
        return origin
    }
}

/// Keyable panel so the size field can accept typing above the overlay.
private final class SizeInputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SizeInputContainerView: NSView, NSTextFieldDelegate {
    weak var field: NSTextField?
    var ratioButtons: [NSButton] = []
    var ratioValues: [CGFloat?] = []
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRatioSelected: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func ratioClicked(_ sender: NSButton) {
        onRatioSelected?(sender.tag)
    }

    @objc func submitClicked() {
        onSubmit?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}
