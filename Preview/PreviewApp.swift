import AppKit

/// A development harness for `MacstifyView`.
///
/// It instantiates the real screen saver view rather than talking to the
/// engine directly, so running it also proves the view is constructible
/// outside System Settings — the failure that otherwise only shows up as an
/// empty preview thumbnail after installing.
///
///     MacstifyPreview                              # live window
///     MacstifyPreview --options                    # live window + Options sheet
///     MacstifyPreview --snapshot out.png           # render frames, write a PNG
///     MacstifyPreview --snapshot out.png --frames 900 --size 1920x1080
///     MacstifyPreview --snapshot out.png --preview # as the System Settings thumbnail
///     MacstifyPreview --snapshot out.png --options # render the Options sheet instead
@main
enum PreviewApp {
    private static var delegate: PreviewDelegate?

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
                         isPreview: options.isPreview)
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

    private static func snapshot(to path: String, size: NSSize, frames: Int, isPreview: Bool) {
        // Enough of AppKit to make NSColor and view drawing usable.
        _ = NSApplication.shared

        let frame = NSRect(origin: .zero, size: size)
        guard let view = MacstifyView(frame: frame, isPreview: isPreview) else {
            FileHandle.standardError.write(Data("failed to create MacstifyView\n".utf8))
            exit(1)
        }

        // An offscreen window gives the view a backing store to cache into.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = view

        for _ in 0..<frames {
            view.animateOneFrame()
        }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("failed to allocate a bitmap\n".utf8))
            exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: rep)

        write(rep, to: path)
        print("wrote \(path) (\(Int(size.width))x\(Int(size.height)), \(frames) frames)")
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct Options {
    var snapshotPath: String?
    var frames = 600
    var size = NSSize(width: 1280, height: 800)
    var showOptions = false
    var isPreview = false

    init(_ arguments: some Sequence<String>) throws {
        var explicitSize = false
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--snapshot":
                snapshotPath = try Self.value(after: argument, from: &iterator)
            case "--frames":
                let raw = try Self.value(after: argument, from: &iterator)
                guard let value = Int(raw), value > 0 else {
                    throw OptionError("--frames expects a positive integer, got \(raw)")
                }
                frames = value
            case "--size":
                let raw = try Self.value(after: argument, from: &iterator)
                let parts = raw.lowercased().split(separator: "x")
                guard parts.count == 2,
                      let width = Double(parts[0]), let height = Double(parts[1]),
                      width > 0, height > 0 else {
                    throw OptionError("--size expects WIDTHxHEIGHT, got \(raw)")
                }
                size = NSSize(width: width, height: height)
                explicitSize = true
            case "--options":
                showOptions = true
            case "--preview":
                isPreview = true
            default:
                throw OptionError("unknown argument: \(argument)")
            }
        }

        // Match the System Settings thumbnail unless a size was asked for.
        if isPreview, !explicitSize {
            size = NSSize(width: 320, height: 200)
        }
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
    init(_ message: String) { errorDescription = message }
}
