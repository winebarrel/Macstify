import AppKit

/// A development harness for the screen saver.
///
/// The live window hosts the real `MacstifyView`, so running it proves the
/// view is constructible outside System Settings — the failure that otherwise
/// only shows up as an empty preview after installing. Snapshots drive
/// `MacstifyEngine` directly instead, which is what lets `--speed` apply to a
/// single render.
///
///     MacstifyPreview                              # live window
///     MacstifyPreview --options                    # live window + Options sheet
///     MacstifyPreview --snapshot out.png           # render frames, write a PNG
///     MacstifyPreview --snapshot out.png --frames 900 --size 1920x1080
///     MacstifyPreview --snapshot out.png --preview # as the System Settings thumbnail
///     MacstifyPreview --snapshot out.png --speed 4 # override the saved speed
///     MacstifyPreview --snapshot out.png --options # render the Options sheet instead
///
/// `--size` is in points; snapshots are written at 2x, as on a Retina display.
@main
@MainActor
enum PreviewApp {
    private static var delegate: PreviewDelegate?

    // Called by the Swift runtime through @main, never from code.
    // swiftlint:disable:next unused_declaration
    static func main() {
        let options: Options
        do {
            options = try Options(CommandLine.arguments.dropFirst())
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }

        if let path = options.snapshotPath {
            if options.showOptions {
                snapshotOptionsSheet(to: path)
            } else {
                snapshot(to: path, size: options.size, frames: options.frames,
                         isPreview: options.isPreview, speed: options.speed)
            }
        } else {
            runLive(size: options.size, showOptions: options.showOptions,
                    isPreview: options.isPreview)
        }
    }

    // MARK: - Live window

    private static func runLive(size: NSSize, showOptions: Bool, isPreview: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let delegate = PreviewDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.mainMenu = makeMenu()

        let frame = NSRect(origin: .zero, size: size)
        guard let view = MacstifyView(frame: frame, isPreview: isPreview) else {
            FileHandle.standardError.write(Data("failed to create MacstifyView\n".utf8))
            exit(1)
        }

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Macstify Preview"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)

        view.startAnimation()

        if showOptions, let sheet = view.configureSheet {
            window.beginSheet(sheet)
        }

        app.activate(ignoringOtherApps: true)
        app.run()
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Macstify Preview",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        return menu
    }

    // MARK: - Snapshot

    /// Steps the engine offscreen and writes the result as a PNG.
    ///
    /// This drives `MacstifyEngine` rather than the view, so `--speed` can
    /// override a setting for one render without writing to the preferences
    /// the installed saver reads.
    private static func snapshot(
        to path: String,
        size: NSSize,
        frames: Int,
        isPreview: Bool,
        speed: Double?
    ) {
        // Enough of AppKit to make NSColor usable.
        _ = NSApplication.shared

        var settings = MacstifySettings.load()
        if isPreview {
            settings = settings.previewAdjusted
        }
        if let speed {
            settings.speed = speed
        }

        let rect = NSRect(origin: .zero, size: size)
        let engine = MacstifyEngine(settings: settings)
        engine.reset(bounds: rect)
        for _ in 0 ..< frames {
            engine.step(dt: 1.0 / 60.0)
        }

        // `size` is in points; render at 2x as a Retina display would.
        let scale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            FileHandle.standardError.write(Data("failed to allocate a bitmap\n".utf8))
            exit(1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        engine.draw(in: rect, context: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        write(rep, to: path)
        print("wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh) px, \(frames) frames)")
    }

    /// Renders the Options sheet offscreen, so its layout can be checked
    /// without a screen-recording entitlement.
    private static func snapshotOptionsSheet(to path: String) {
        _ = NSApplication.shared

        let controller = ConfigureSheetController { _ in }
        guard let content = controller.window.contentView else {
            FileHandle.standardError.write(Data("the sheet has no content view\n".utf8))
            exit(1)
        }
        content.layoutSubtreeIfNeeded()

        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            FileHandle.standardError.write(Data("failed to allocate a bitmap\n".utf8))
            exit(1)
        }
        content.cacheDisplay(in: content.bounds, to: rep)

        write(rep, to: path)
        print("wrote \(path) (Options sheet, \(Int(content.bounds.width))x\(Int(content.bounds.height)))")
    }

    private static func write(_ rep: NSBitmapImageRep, to path: String) {
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

private struct Options {
    var snapshotPath: String?
    var frames = 600
    var size = NSSize(width: 1280, height: 800)
    var showOptions = false
    var isPreview = false
    var speed: Double?

    init(_ arguments: some Sequence<String>) throws {
        var explicitSize = false
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--options":
                showOptions = true
            case "--preview":
                isPreview = true
            case "--snapshot", "--frames", "--size", "--speed":
                let raw = try Self.value(after: argument, from: &iterator)
                try set(argument, to: raw, explicitSize: &explicitSize)
            default:
                // Xcode launches the app with NSUserDefaults-style arguments
                // such as `-NSDocumentRevisionsDebugMode YES`. Rejecting those
                // means Run quits before the window ever appears, so skip any
                // single-dash flag and the value that follows it. A misspelt
                // `--option` still fails loudly.
                guard argument.hasPrefix("--") else {
                    _ = iterator.next()
                    continue
                }
                throw OptionError("unknown argument: \(argument)")
            }
        }

        // Match the System Settings thumbnail unless a size was asked for.
        if isPreview, !explicitSize {
            size = NSSize(width: 320, height: 200)
        }
    }

    private mutating func set(_ flag: String, to raw: String, explicitSize: inout Bool) throws {
        switch flag {
        case "--snapshot":
            snapshotPath = raw
        case "--frames":
            guard let value = Int(raw), value > 0 else {
                throw OptionError("\(flag) expects a positive integer, got \(raw)")
            }
            frames = value
        case "--size":
            size = try Self.parseSize(raw)
            explicitSize = true
        default:
            guard let value = Double(raw), value > 0 else {
                throw OptionError("\(flag) expects a positive number, got \(raw)")
            }
            speed = value
        }
    }

    private static func parseSize(_ raw: String) throws -> NSSize {
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0
        else {
            throw OptionError("--size expects WIDTHxHEIGHT, got \(raw)")
        }
        return NSSize(width: width, height: height)
    }

    private static func value(
        after flag: String,
        from iterator: inout some IteratorProtocol<String>
    ) throws -> String {
        guard let value = iterator.next() else {
            throw OptionError("\(flag) requires a value")
        }
        return value
    }
}

private struct OptionError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) {
        errorDescription = message
    }
}
