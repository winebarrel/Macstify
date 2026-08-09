import ScreenSaver

/// The screen saver's principal class.
///
/// `@objc(MacstifyView)` strips the Swift module prefix so the name matches
/// `NSPrincipalClass` in `Sources/Info.plist`; without it the host process
/// looks up `Macstify.MacstifyView` and finds nothing.
@objc(MacstifyView)
final class MacstifyView: ScreenSaverView {
    private let engine: MacstifyEngine
    /// Held strongly: the host releases its reference once the sheet is up,
    /// and a deallocated controller takes the sheet's targets with it.
    private var sheetController: ConfigureSheetController?

    override init?(frame: NSRect, isPreview: Bool) {
        engine = MacstifyEngine(settings: Self.settings(isPreview: isPreview))
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        engine.reset(bounds: bounds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override func startAnimation() {
        super.startAnimation()
        // Picks up any change made through the configuration sheet.
        engine.apply(Self.settings(isPreview: isPreview))
    }

    override func animateOneFrame() {
        super.animateOneFrame()
        engine.step(dt: animationTimeInterval)
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        engine.draw(in: bounds, context: context)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        engine.resize(to: bounds)
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let controller = ConfigureSheetController { [weak self] saved in
            guard let self else { return }
            if saved {
                engine.apply(Self.settings(isPreview: isPreview))
            }
            sheetController = nil
        }
        sheetController = controller
        return controller.window
    }

    private static func settings(isPreview: Bool) -> MacstifySettings {
        let settings = MacstifySettings.load()
        return isPreview ? settings.previewAdjusted : settings
    }
}
