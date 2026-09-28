import AppKit

final class CaptureTextWatermarkSettings: NSView {
    private let textCard = TextFontSettingsCard()
    private let watermarkCard = WatermarkSettingsCard()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [textCard, watermarkCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            textCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            watermarkCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        textCard.onFontChanged = { [weak watermarkCard] in
            watermarkCard?.refreshPreview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshLocalization() {
        textCard.refreshLocalization()
        watermarkCard.refreshLocalization()
    }
}

private final class TextFontSettingsCard: NSView {
    var onFontChanged: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let fontLabel = NSTextField(labelWithString: "")
    private let fontPopup = FontFamilyPopup(mode: .systemDefault)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        styleAsSettingsCard(self)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        hintLabel.preferredMaxLayoutWidth = 420
        fontLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        fontLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        fontPopup.onChange = { [weak self] family in
            Defaults.textFontFamily = family
            self?.onFontChanged?()
        }
        let row = NSStackView(views: [fontLabel, NSView(), fontPopup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        let stack = NSStackView(views: [titleLabel, hintLabel, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fontPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        refreshLocalization()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshLocalization() {
        titleLabel.stringValue = L10n.textFontSectionTitle
        hintLabel.stringValue = L10n.textFontHint
        fontLabel.stringValue = L10n.textFontLabel
        fontPopup.configure(specialTitle: L10n.textFontSystemDefault, family: Defaults.textFontFamily)
    }
}

private final class WatermarkSettingsCard: NSView, NSTextFieldDelegate {
    private let titleLabel = NSTextField(labelWithString: "")
    private let toggleTitle = NSTextField(labelWithString: "")
    private let toggleHint = NSTextField(wrappingLabelWithString: "")
    private let toggle = NSSwitch()
    private let body = NSStackView()
    private let listStack = NSStackView()
    private let addButton = NSButton()
    private let form = NSStackView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let nameField = NSTextField()
    private let textLabel = NSTextField(labelWithString: "")
    private let textField = NSTextField()
    private let fontLabel = NSTextField(labelWithString: "")
    private let fontPopup = FontFamilyPopup(mode: .followText)
    private let sizeLabel = NSTextField(labelWithString: "")
    private let sizeValue = NSTextField(labelWithString: "")
    private let sizeSlider = NSSlider()
    private let colorLabel = NSTextField(labelWithString: "")
    private let colorRow = NSStackView()
    private var colorSwatches: [SettingsColorSwatch] = []
    private let strokeLabel = NSTextField(labelWithString: "")
    private let strokeSwitch = NSSwitch()
    private let opacityLabel = NSTextField(labelWithString: "")
    private let opacityValue = NSTextField(labelWithString: "")
    private let opacitySlider = NSSlider()
    private let positionLabel = NSTextField(labelWithString: "")
    private var anchorButtons: [NSButton] = []
    private let marginLabel = NSTextField(labelWithString: "")
    private let marginValue = NSTextField(labelWithString: "")
    private let marginSlider = NSSlider()
    private let previewLabel = NSTextField(labelWithString: "")
    private let preview = WatermarkPreviewView()
    private var templates: [WatermarkTemplate] = []
    private var selectedID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        styleAsSettingsCard(self)
        templates = Defaults.watermarkTemplates
        if let raw = Defaults.selectedWatermarkTemplateID, let id = UUID(uuidString: raw),
           templates.contains(where: { $0.id == id }) {
            selectedID = id
        }
        build()
        reloadForm()
        refreshEnabled()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshLocalization() {
        titleLabel.stringValue = L10n.watermarkSectionTitle
        toggleTitle.stringValue = L10n.watermarkToggleLabel
        toggleHint.stringValue = L10n.watermarkToggleHint
        addButton.title = L10n.watermarkAdd
        nameLabel.stringValue = L10n.watermarkNameLabel
        textLabel.stringValue = L10n.watermarkTextLabel
        textField.placeholderString = L10n.watermarkTextPlaceholder
        fontLabel.stringValue = L10n.watermarkFontLabel
        sizeLabel.stringValue = L10n.watermarkSizeLabel
        colorLabel.stringValue = L10n.watermarkColorLabel
        strokeLabel.stringValue = L10n.watermarkStrokeLabel
        opacityLabel.stringValue = L10n.watermarkOpacityLabel
        positionLabel.stringValue = L10n.watermarkPositionLabel
        marginLabel.stringValue = L10n.watermarkMarginLabel
        previewLabel.stringValue = L10n.watermarkPreviewLabel
        preview.hint = L10n.watermarkEmptyTextHint
        fontPopup.configure(specialTitle: L10n.watermarkFontFollowText, family: selectedTemplate?.fontFamily)
        for (index, button) in anchorButtons.enumerated() where index < WatermarkAnchor.allCases.count {
            let anchor = WatermarkAnchor.allCases[index]
            button.toolTip = anchor.localizedName
            button.setAccessibilityLabel(anchor.localizedName)
        }
        rebuildList()
    }

    func refreshPreview() {
        preview.template = selectedTemplate
    }

    private var selectedTemplate: WatermarkTemplate? {
        templates.first { $0.id == selectedID }
    }

    private func build() {
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        toggleTitle.font = titleLabel.font
        toggleTitle.textColor = titleLabel.textColor
        toggleHint.font = NSFont.systemFont(ofSize: 11)
        toggleHint.textColor = NSColor.white.withAlphaComponent(0.58)
        toggleHint.preferredMaxLayoutWidth = 420
        toggle.controlSize = .small
        toggle.state = Defaults.watermarkEnabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        let textColumn = NSStackView(views: [toggleTitle, toggleHint])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 2
        let toggleRow = NSStackView(views: [textColumn, NSView(), toggle])
        toggleRow.orientation = .horizontal
        toggleRow.alignment = .centerY

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 4
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        addButton.font = NSFont.systemFont(ofSize: 12)
        addButton.target = self
        addButton.action = #selector(addTemplate)
        configureField(nameField)
        configureField(textField)
        textField.cell?.wraps = true
        textField.cell?.isScrollable = true
        textField.maximumNumberOfLines = 4
        nameField.delegate = self
        textField.delegate = self
        fontPopup.onChange = { [weak self] family in
            self?.updateSelected { $0.fontFamily = family }
        }
        configureSlider(sizeSlider, min: 10, max: 100, action: #selector(sizeChanged(_:)))
        configureSlider(opacitySlider, min: 20, max: 100, action: #selector(opacityChanged(_:)))
        configureSlider(marginSlider, min: 0, max: 160, action: #selector(marginChanged(_:)))
        styleValue(sizeValue)
        styleValue(opacityValue)
        styleValue(marginValue)
        strokeSwitch.controlSize = .small
        strokeSwitch.target = self
        strokeSwitch.action = #selector(strokeChanged(_:))
        colorRow.orientation = .horizontal
        colorRow.spacing = 6
        for color in EditorStyleDefaults.paletteColors {
            let swatch = SettingsColorSwatch()
            swatch.swatch = color
            swatch.hex = Self.hex(for: color)
            swatch.target = self
            swatch.action = #selector(colorPicked(_:))
            swatch.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 18),
                swatch.heightAnchor.constraint(equalToConstant: 18),
            ])
            colorSwatches.append(swatch)
            colorRow.addArrangedSubview(swatch)
        }
        let anchorGrid = NSStackView()
        anchorGrid.orientation = .vertical
        anchorGrid.spacing = 4
        var row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        for (index, anchor) in WatermarkAnchor.allCases.enumerated() {
            if index > 0, index % 3 == 0 {
                anchorGrid.addArrangedSubview(row)
                row = NSStackView()
                row.orientation = .horizontal
                row.spacing = 4
            }
            let button = NSButton(title: anchor.symbol, target: self, action: #selector(anchorPicked(_:)))
            button.bezelStyle = .rounded
            button.tag = index
            button.font = NSFont.systemFont(ofSize: 12)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            anchorButtons.append(button)
            row.addArrangedSubview(button)
        }
        anchorGrid.addArrangedSubview(row)

        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.translatesAutoresizingMaskIntoConstraints = false
        form.addArrangedSubview(labeledRow(nameLabel, nameField))
        form.addArrangedSubview(labeledRow(textLabel, textField))
        textField.heightAnchor.constraint(equalToConstant: 52).isActive = true
        form.addArrangedSubview(labeledRow(fontLabel, fontPopup))
        form.addArrangedSubview(sliderRow(sizeLabel, sizeSlider, sizeValue))
        form.addArrangedSubview(labeledRow(colorLabel, colorRow))
        form.addArrangedSubview(labeledRow(strokeLabel, strokeSwitch))
        form.addArrangedSubview(sliderRow(opacityLabel, opacitySlider, opacityValue))
        form.addArrangedSubview(labeledRow(positionLabel, anchorGrid))
        form.addArrangedSubview(sliderRow(marginLabel, marginSlider, marginValue))
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 120).isActive = true
        for label in [nameLabel, textLabel, fontLabel, sizeLabel, colorLabel, strokeLabel, opacityLabel, positionLabel, marginLabel, previewLabel] {
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.88)
        }
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(listStack)
        body.addArrangedSubview(addButton)
        body.addArrangedSubview(form)
        body.addArrangedSubview(previewLabel)
        body.addArrangedSubview(preview)

        let outer = NSStackView(views: [titleLabel, toggleRow, body])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 10
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            toggleRow.widthAnchor.constraint(equalTo: outer.widthAnchor),
            body.widthAnchor.constraint(equalTo: outer.widthAnchor),
            listStack.widthAnchor.constraint(equalTo: body.widthAnchor),
            form.widthAnchor.constraint(equalTo: body.widthAnchor),
            preview.widthAnchor.constraint(equalTo: body.widthAnchor),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            fontPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        refreshLocalization()
    }

    @objc private func toggleChanged(_ sender: NSSwitch) {
        Defaults.watermarkEnabled = sender.state == .on
        if sender.state == .on, templates.isEmpty {
            addTemplate()
        } else if sender.state == .on, selectedID == nil {
            selectedID = templates.first?.id
            Defaults.selectedWatermarkTemplateID = selectedID?.uuidString
            rebuildList()
            reloadForm()
        }
        refreshEnabled()
    }

    @objc private func addTemplate() {
        guard templates.count < WatermarkTemplate.maxCount else { return }
        let template = WatermarkTemplate.makeNew(displayIndex: templates.count + 1)
        templates.append(template)
        selectedID = template.id
        persist()
        rebuildList()
        reloadForm()
        refreshEnabled()
        window?.makeFirstResponder(textField)
    }

    @objc private func selectTemplate(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        selectedID = id
        Defaults.selectedWatermarkTemplateID = id.uuidString
        rebuildList()
        reloadForm()
    }

    @objc private func duplicateTemplate(_ sender: NSButton) {
        guard templates.count < WatermarkTemplate.maxCount,
              let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw),
              let template = templates.first(where: { $0.id == id })
        else { return }
        var copy = template
        copy.id = UUID()
        copy.name = String(template.name.prefix(36)) + " 2"
        templates.append(copy)
        selectedID = copy.id
        persist()
        rebuildList()
        reloadForm()
        refreshEnabled()
    }

    @objc private func deleteTemplate(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        templates.removeAll { $0.id == id }
        if selectedID == id { selectedID = templates.first?.id }
        persist()
        rebuildList()
        reloadForm()
        refreshEnabled()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        updateSelected { $0.fontSize = sender.doubleValue.rounded() }
        sizeValue.stringValue = "\(Int(sender.doubleValue.rounded()))"
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let percent = sender.doubleValue.rounded()
        updateSelected { $0.opacity = percent / 100 }
        opacityValue.stringValue = "\(Int(percent))"
    }

    @objc private func marginChanged(_ sender: NSSlider) {
        updateSelected { $0.margin = sender.doubleValue.rounded() }
        marginValue.stringValue = "\(Int(sender.doubleValue.rounded()))"
    }

    @objc private func strokeChanged(_ sender: NSSwitch) {
        updateSelected { $0.hasStroke = sender.state == .on }
    }

    @objc private func colorPicked(_ sender: SettingsColorSwatch) {
        updateSelected { $0.colorHex = sender.hex }
        refreshColorSelection()
    }

    @objc private func anchorPicked(_ sender: NSButton) {
        guard WatermarkAnchor.allCases.indices.contains(sender.tag) else { return }
        let anchor = WatermarkAnchor.allCases[sender.tag]
        updateSelected { $0.anchor = anchor }
        refreshAnchorSelection()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, var template = selectedTemplate, let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        if field === nameField {
            template.name = field.stringValue
        } else if field === textField {
            template.text = field.stringValue
        } else {
            return
        }
        templates[index] = template
        persist()
        preview.template = template
        if field === nameField {
            updateSelectedRowTitle(template.name)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === nameField else { return }
        templates = Defaults.watermarkTemplates
        if selectedID == nil || !templates.contains(where: { $0.id == selectedID }) {
            selectedID = templates.first?.id
        }
        reloadForm()
        rebuildList()
    }

    private func updateSelected(_ change: (inout WatermarkTemplate) -> Void) {
        guard let index = templates.firstIndex(where: { $0.id == selectedID }) else { return }
        change(&templates[index])
        persist()
        preview.template = templates[index]
    }

    private func persist() {
        Defaults.watermarkTemplates = templates
        Defaults.selectedWatermarkTemplateID = selectedID?.uuidString
        templates = Defaults.watermarkTemplates
        if let selectedID, !templates.contains(where: { $0.id == selectedID }) {
            self.selectedID = templates.first?.id
            Defaults.selectedWatermarkTemplateID = self.selectedID?.uuidString
        }
    }

    private func rebuildList() {
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let canMutate = templates.count < WatermarkTemplate.maxCount
        addButton.isEnabled = canMutate && Defaults.watermarkEnabled
        for template in templates {
            let select = NSButton(title: template.name, target: self, action: #selector(selectTemplate(_:)))
            select.bezelStyle = .inline
            select.isBordered = false
            select.alignment = .left
            select.font = NSFont.systemFont(ofSize: 12, weight: template.id == selectedID ? .semibold : .regular)
            select.contentTintColor = template.id == selectedID
                ? .controlAccentColor
                : NSColor.white.withAlphaComponent(0.9)
            select.identifier = NSUserInterfaceItemIdentifier(template.id.uuidString)
            select.lineBreakMode = .byTruncatingTail
            let duplicate = smallButton(L10n.watermarkDuplicate, action: #selector(duplicateTemplate(_:)), id: template.id)
            duplicate.isEnabled = canMutate
            let delete = smallButton(L10n.watermarkDelete, action: #selector(deleteTemplate(_:)), id: template.id)
            let row = NSStackView(views: [select, NSView(), duplicate, delete])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
        form.isHidden = selectedTemplate == nil
        preview.isHidden = selectedTemplate == nil
        previewLabel.isHidden = selectedTemplate == nil
    }

    private func reloadForm() {
        guard let template = selectedTemplate else {
            preview.template = nil
            return
        }
        nameField.stringValue = template.name
        textField.stringValue = template.text
        fontPopup.configure(specialTitle: L10n.watermarkFontFollowText, family: template.fontFamily)
        sizeSlider.doubleValue = template.fontSize
        sizeValue.stringValue = "\(Int(template.fontSize.rounded()))"
        opacitySlider.doubleValue = template.opacity * 100
        opacityValue.stringValue = "\(Int((template.opacity * 100).rounded()))"
        marginSlider.doubleValue = template.margin
        marginValue.stringValue = "\(Int(template.margin.rounded()))"
        strokeSwitch.state = template.hasStroke ? .on : .off
        refreshColorSelection()
        refreshAnchorSelection()
        preview.template = template
    }

    private func updateSelectedRowTitle(_ name: String) {
        guard let id = selectedID?.uuidString else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (selectedTemplate?.name ?? name)
            : name
        for case let row as NSStackView in listStack.arrangedSubviews {
            for case let button as NSButton in row.arrangedSubviews
            where button.identifier?.rawValue == id && button.action == #selector(selectTemplate(_:)) {
                button.title = title
            }
        }
    }

    private func refreshColorSelection() {
        let selected = EditorStyleDefaults.normalizedHex(selectedTemplate?.colorHex)
        for swatch in colorSwatches {
            swatch.isChosen = swatch.hex == selected
        }
    }

    private func refreshAnchorSelection() {
        for (index, button) in anchorButtons.enumerated() {
            let chosen = WatermarkAnchor.allCases[index] == selectedTemplate?.anchor
            button.contentTintColor = chosen ? .controlAccentColor : NSColor.white.withAlphaComponent(0.85)
        }
    }

    private func refreshEnabled() {
        let on = Defaults.watermarkEnabled
        setEnabled(body, on)
        body.alphaValue = on ? 1 : 0.45
        addButton.isEnabled = on && templates.count < WatermarkTemplate.maxCount
    }

    private func setEnabled(_ view: NSView, _ enabled: Bool) {
        if let control = view as? NSControl { control.isEnabled = enabled }
        view.subviews.forEach { setEnabled($0, enabled) }
    }

    private func labeledRow(_ label: NSTextField, _ control: NSView) -> NSView {
        let row = NSStackView(views: [label, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        label.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func sliderRow(_ label: NSTextField, _ slider: NSSlider, _ value: NSTextField) -> NSView {
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let row = NSStackView(views: [label, NSView(), slider, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        value.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    private func smallButton(_ title: String, action: Selector, id: UUID) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        button.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        return button
    }

    private func configureField(_ field: NSTextField) {
        field.isEditable = true
        field.isBordered = true
        field.font = NSFont.systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
    }

    private func configureSlider(_ slider: NSSlider, min: Double, max: Double, action: Selector) {
        slider.minValue = min
        slider.maxValue = max
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = action
    }

    private func styleValue(_ label: NSTextField) {
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.88)
        label.alignment = .right
    }

    private static func hex(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}

private final class WatermarkPreviewView: NSView {
    var hint = "" { didSet { needsDisplay = true } }
    var template: WatermarkTemplate? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let canvas = NSSize(width: 320, height: 180)
        guard let template, let annotation = WatermarkLayout.annotation(for: template, canvasSize: canvas) else {
            drawHint()
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(bounds.width / canvas.width, bounds.height / canvas.height)
        context.saveGState()
        context.translateBy(
            x: (bounds.width - canvas.width * scale) / 2,
            y: (bounds.height - canvas.height * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)
        annotation.draw(in: context, bounds: NSRect(origin: .zero, size: canvas))
        context.restoreGState()
    }

    private func drawHint() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = hint as NSString
        let rect = bounds.insetBy(dx: 16, dy: 16)
        text.draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph,
        ])
    }
}

private final class SettingsColorSwatch: NSButton {
    var swatch = NSColor.white { didSet { needsDisplay = true } }
    var hex = "#FFFFFF"
    var isChosen = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        swatch.setFill()
        path.fill()
        if isChosen {
            NSColor.white.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}

private final class FontFamilyPopup: NSPopUpButton {
    enum Mode { case systemDefault, followText }

    var onChange: ((String?) -> Void)?
    private let mode: Mode
    private var specialTitle = ""
    private var selectedFamily: String?
    private var didBuild = false
    private var didScheduleBuild = false
    private var suppressAction = false

    init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero, pullsDown: false)
        controlSize = .small
        font = NSFont.systemFont(ofSize: 12)
        target = self
        action = #selector(picked(_:))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(specialTitle: String, family: String?) {
        self.specialTitle = specialTitle
        selectedFamily = TextFontResolver.normalizedFamily(family)
        if didBuild {
            item(at: 0)?.title = specialTitle
            selectFamily(selectedFamily)
        } else {
            removeAllItems()
            addItem(withTitle: selectedFamily ?? specialTitle)
            lastItem?.representedObject = selectedFamily ?? ""
        }
        scheduleBuildIfNeeded()
    }

    private func scheduleBuildIfNeeded() {
        guard !didBuild, !didScheduleBuild else { return }
        didScheduleBuild = true
        DispatchQueue.main.async { [weak self] in
            self?.ensureBuilt()
        }
    }

    override func mouseDown(with event: NSEvent) {
        ensureBuilt()
        super.mouseDown(with: event)
    }

    override func performClick(_ sender: Any?) {
        ensureBuilt()
        super.performClick(sender)
    }

    private func ensureBuilt() {
        guard !didBuild else { return }
        didBuild = true
        rebuild()
    }

    private func rebuild() {
        let family = selectedFamily
        suppressAction = true
        removeAllItems()
        addItem(withTitle: specialTitle)
        lastItem?.representedObject = ""
        for name in TextFontResolver.availableFamilies() {
            let item = NSMenuItem()
            let face = TextFontResolver.font(family: name, size: 13)
            item.attributedTitle = NSAttributedString(string: name, attributes: [
                .font: face,
                .foregroundColor: NSColor.labelColor,
            ])
            item.representedObject = name
            menu?.addItem(item)
        }
        selectFamily(family)
        suppressAction = false
    }

    private func selectFamily(_ family: String?) {
        suppressAction = true
        if let family, let item = menu?.items.first(where: { ($0.representedObject as? String) == family }) {
            select(item)
        } else {
            selectItem(at: 0)
        }
        suppressAction = false
    }

    @objc private func picked(_ sender: NSPopUpButton) {
        guard !suppressAction else { return }
        let raw = sender.selectedItem?.representedObject as? String ?? ""
        selectedFamily = raw.isEmpty ? nil : raw
        onChange?(selectedFamily)
    }
}

private func styleAsSettingsCard(_ view: NSView) {
    view.wantsLayer = true
    view.layer?.cornerRadius = 12
    view.layer?.cornerCurve = .continuous
    view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
    view.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
    view.layer?.borderWidth = 1
}
