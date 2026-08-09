import AppKit

/// The "Options…" sheet, built in code.
///
/// A nib would have to be located inside the loaded bundle at runtime, which
/// is a common source of breakage for screen savers; assembling the controls
/// directly avoids that failure mode entirely.
@MainActor
final class ConfigureSheetController: NSObject {
    /// A labelled control bound to one field of `MacstifySettings`.
    private struct Row {
        let control: NSControl
        let valueLabel: NSTextField
        let describe: (Double) -> String
        let read: (MacstifySettings) -> Double
        let write: (inout MacstifySettings, Double) -> Void
    }

    let window: NSWindow

    private var settings = MacstifySettings.load()
    private let onDismiss: (_ saved: Bool) -> Void
    private var rows: [Row] = []

    init(onDismiss: @escaping (_ saved: Bool) -> Void) {
        self.onDismiss = onDismiss
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Macstify"
        buildInterface()
        refresh()
    }

    // MARK: - Interface

    private func buildInterface() {
        let integer: (Double) -> String = { String(Int($0.rounded())) }
        let multiplier: (Double) -> String = { String(format: "%.2f×", $0) }

        let gridRows: [[NSView]] = [
            makeRow(
                title: "Shapes:",
                control: makeStepper(range: MacstifySettings.polygonCountRange),
                describe: integer,
                read: { Double($0.polygonCount) },
                write: { $0.polygonCount = Int($1.rounded()) }
            ),
            makeRow(
                title: "Vertices:",
                control: makeStepper(range: MacstifySettings.vertexCountRange),
                describe: integer,
                read: { Double($0.vertexCount) },
                write: { $0.vertexCount = Int($1.rounded()) }
            ),
            makeRow(
                title: "Trail length:",
                control: makeSlider(range: MacstifySettings.trailLengthRange),
                describe: integer,
                read: { Double($0.trailLength) },
                write: { $0.trailLength = Int($1.rounded()) }
            ),
            makeRow(
                title: "Speed:",
                control: makeSlider(range: MacstifySettings.speedRange),
                describe: multiplier,
                read: { $0.speed },
                write: { $0.speed = $1 }
            ),
            makeRow(
                title: "Line width:",
                control: makeSlider(range: MacstifySettings.lineWidthRange),
                describe: { String(format: "%.1f pt", $0) },
                read: { $0.lineWidth },
                write: { $0.lineWidth = $1 }
            ),
            makeRow(
                title: "Color speed:",
                control: makeSlider(range: MacstifySettings.colorSpeedRange),
                describe: multiplier,
                read: { $0.colorSpeed },
                write: { $0.colorSpeed = $1 }
            ),
        ]

        let grid = NSGridView(views: gridRows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 10

        let restore = NSButton(title: "Restore Defaults", target: self,
                               action: #selector(restoreDefaults))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.setViews([restore], in: .leading)
        buttons.setViews([cancel, ok], in: .trailing)

        let root = NSStackView(views: [grid, buttons])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
    }

    private func makeRow(
        title: String,
        control: NSControl,
        describe: @escaping (Double) -> String,
        read: @escaping (MacstifySettings) -> Double,
        write: @escaping (inout MacstifySettings, Double) -> Void
    ) -> [NSView] {
        control.target = self
        control.action = #selector(controlChanged(_:))

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.alignment = .right
        // Monospaced digits and a fixed width keep the grid from twitching as
        // the numbers change under the slider.
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        rows.append(Row(control: control, valueLabel: valueLabel,
                        describe: describe, read: read, write: write))

        return [NSTextField(labelWithString: title), control, valueLabel]
    }

    private func makeStepper(range: ClosedRange<Int>) -> NSStepper {
        let stepper = NSStepper()
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.autorepeat = true
        return stepper
    }

    private func makeSlider(range: ClosedRange<Double>) -> NSSlider {
        let slider = NSSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return slider
    }

    private func makeSlider(range: ClosedRange<Int>) -> NSSlider {
        makeSlider(range: Double(range.lowerBound)...Double(range.upperBound))
    }

    /// Pushes `settings` back out to every control, so one refresh path serves
    /// both the initial load and "Restore Defaults".
    private func refresh() {
        for row in rows {
            let value = row.read(settings)
            row.control.doubleValue = value
            row.valueLabel.stringValue = row.describe(value)
        }
    }

    // MARK: - Actions

    @objc private func controlChanged(_ sender: NSControl) {
        guard let row = rows.first(where: { $0.control === sender }) else { return }
        row.write(&settings, sender.doubleValue)
        refresh()
    }

    @objc private func restoreDefaults() {
        settings = .standard
        refresh()
    }

    @objc private func confirm() {
        settings.save()
        dismiss(saved: true)
    }

    @objc private func cancel() {
        dismiss(saved: false)
    }

    private func dismiss(saved: Bool) {
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: saved ? .OK : .cancel)
        } else {
            // Reachable from the preview app, which shows the sheet standalone.
            if NSApp.modalWindow === window { NSApp.stopModal() }
            window.orderOut(nil)
        }
        onDismiss(saved)
    }
}
