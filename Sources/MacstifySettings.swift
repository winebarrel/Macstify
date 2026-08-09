import Foundation
import ScreenSaver

/// User-tunable parameters, persisted through `ScreenSaverDefaults`.
///
/// A screen saver bundle is loaded by several different host applications
/// (System Settings, `legacyScreenSaver`, ...), so `UserDefaults.standard`
/// would resolve to a different domain depending on who loaded us.
/// `ScreenSaverDefaults` pins the domain to our bundle identifier instead.
struct MacstifySettings: Equatable {
    /// Must match `CFBundleIdentifier` in `Sources/Info.plist`.
    static let moduleName = "jp.winebarrel.Macstify"

    var polygonCount: Int
    var vertexCount: Int
    var trailLength: Int
    var speed: Double
    var lineWidth: Double
    var colorSpeed: Double

    static let standard = MacstifySettings(
        polygonCount: 2,
        vertexCount: 4,
        trailLength: 12,
        speed: 1.0,
        lineWidth: 1.5,
        colorSpeed: 1.0
    )

    static let polygonCountRange = 1...8
    static let vertexCountRange = 3...12
    static let trailLengthRange = 1...40
    static let speedRange = 0.2...3.0
    static let lineWidthRange = 0.5...4.0
    static let colorSpeedRange = 0.0...3.0

    private enum Key {
        static let polygonCount = "polygonCount"
        static let vertexCount = "vertexCount"
        static let trailLength = "trailLength"
        static let speed = "speed"
        static let lineWidth = "lineWidth"
        static let colorSpeed = "colorSpeed"
    }

    private static var store: ScreenSaverDefaults? {
        let defaults = ScreenSaverDefaults(forModuleWithName: moduleName)
        defaults?.register(defaults: [
            Key.polygonCount: standard.polygonCount,
            Key.vertexCount: standard.vertexCount,
            Key.trailLength: standard.trailLength,
            Key.speed: standard.speed,
            Key.lineWidth: standard.lineWidth,
            Key.colorSpeed: standard.colorSpeed,
        ])
        return defaults
    }

    /// Reads the saved settings, clamping every value so that a hand-edited
    /// preference file can never produce a degenerate polygon or a stalled
    /// animation.
    static func load() -> MacstifySettings {
        guard let store else { return standard }
        return MacstifySettings(
            polygonCount: polygonCountRange.clamping(store.integer(forKey: Key.polygonCount)),
            vertexCount: vertexCountRange.clamping(store.integer(forKey: Key.vertexCount)),
            trailLength: trailLengthRange.clamping(store.integer(forKey: Key.trailLength)),
            speed: speedRange.clamping(store.double(forKey: Key.speed)),
            lineWidth: lineWidthRange.clamping(store.double(forKey: Key.lineWidth)),
            colorSpeed: colorSpeedRange.clamping(store.double(forKey: Key.colorSpeed))
        )
    }

    func save() {
        guard let store = Self.store else { return }
        store.set(polygonCount, forKey: Key.polygonCount)
        store.set(vertexCount, forKey: Key.vertexCount)
        store.set(trailLength, forKey: Key.trailLength)
        store.set(speed, forKey: Key.speed)
        store.set(lineWidth, forKey: Key.lineWidth)
        store.set(colorSpeed, forKey: Key.colorSpeed)
        store.synchronize()
    }
}

private extension ClosedRange where Bound: Comparable {
    func clamping(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
