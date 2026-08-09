import AppKit

/// Simulation and drawing for the Mystify effect.
///
/// Deliberately free of any `NSView` dependency: it takes a rect and a
/// `CGContext`, so the same code drives the screen saver, the preview app's
/// live window and the offscreen PNG snapshots.
final class MacstifyEngine {
    /// One historical position of a polygon, kept so the shape leaves a trail.
    private struct Ghost {
        var points: [CGPoint]
        var hue: Double
    }

    private struct Polygon {
        var points: [CGPoint]
        var velocities: [CGVector]
        var hue: Double
        var hueSpeed: Double
        /// Oldest first, newest last.
        var trail: [Ghost]
    }

    /// Vertex travel per second at `speed == 1.0`, as a fraction of the
    /// shorter edge of the screen. Keeps the perceived pace identical on a
    /// laptop panel and on a 5K display.
    private static let baseSpeedRatio = 0.10
    /// Hue revolutions per second at `colorSpeed == 1.0`.
    private static let baseHueSpeed = 0.05
    /// How often a ghost is recorded, independent of the frame rate.
    ///
    /// The original redrew at roughly this rate and left one outline behind
    /// per redraw. Sampling on a timer instead of once per frame keeps that
    /// spacing — at 60 fps a per-frame trail would pile every outline into a
    /// few points of travel and read as a single fat line — while the live
    /// shape still moves smoothly.
    private static let ghostInterval: TimeInterval = 0.125

    private(set) var settings: MacstifySettings
    private var bounds: CGRect = .zero
    private var polygons: [Polygon] = []
    private var timeSinceGhost: TimeInterval = 0

    /// Ghosts to keep. `trailLength` counts the outlines actually on screen,
    /// and the live shape is one of them.
    private var ghostCapacity: Int {
        max(0, settings.trailLength - 1)
    }

    init(settings: MacstifySettings = .load()) {
        self.settings = settings
    }

    /// Applies new settings, restarting the simulation only when a structural
    /// parameter changed. Speed and colour tweaks stay smooth.
    func apply(_ newSettings: MacstifySettings) {
        let needsRestart = newSettings.polygonCount != settings.polygonCount
            || newSettings.vertexCount != settings.vertexCount
        let speedRatio = settings.speed > 0 ? newSettings.speed / settings.speed : 1
        settings = newSettings

        if needsRestart {
            reset(bounds: bounds)
            return
        }

        let hueSpeed = Self.baseHueSpeed * newSettings.colorSpeed
        for index in polygons.indices {
            polygons[index].hueSpeed = hueSpeed
            if speedRatio != 1 {
                polygons[index].velocities = polygons[index].velocities.map {
                    CGVector(dx: $0.dx * speedRatio, dy: $0.dy * speedRatio)
                }
            }
            if polygons[index].trail.count > ghostCapacity {
                polygons[index].trail.removeFirst(polygons[index].trail.count - ghostCapacity)
            }
        }
    }

    /// Rebuilds every polygon with fresh random positions and velocities.
    func reset(bounds newBounds: CGRect) {
        bounds = newBounds
        polygons = []
        timeSinceGhost = 0

        let area = field
        guard area.width > 0, area.height > 0 else { return }

        let speed = min(area.width, area.height) * Self.baseSpeedRatio * settings.speed
        // One shared rate: every shape keeps its initial slice of the colour
        // wheel forever. Per-shape rates let the hues drift together after a
        // minute or two, which reads as a bug rather than as palette cycling.
        let hueSpeed = Self.baseHueSpeed * settings.colorSpeed

        polygons = (0 ..< settings.polygonCount).map { index in
            // Spread the starting hues so the shapes never launch in unison.
            let hue = Double(index) / Double(settings.polygonCount)

            var points: [CGPoint] = []
            var velocities: [CGVector] = []
            for _ in 0 ..< settings.vertexCount {
                points.append(CGPoint(
                    x: Double.random(in: area.minX ... area.maxX),
                    y: Double.random(in: area.minY ... area.maxY)
                ))
                // Independent per-vertex velocity is what makes the polygon
                // churn through shapes instead of drifting rigidly.
                let angle = Double.random(in: 0 ..< (2 * .pi))
                let magnitude = speed * Double.random(in: 0.6 ... 1.4)
                velocities.append(CGVector(dx: cos(angle) * magnitude, dy: sin(angle) * magnitude))
            }

            return Polygon(points: points, velocities: velocities,
                           hue: hue, hueSpeed: hueSpeed, trail: [])
        }
    }

    /// Rescales the simulation in place so a resize never teleports the shapes.
    func resize(to newBounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else {
            reset(bounds: newBounds)
            return
        }
        guard newBounds.width > 0, newBounds.height > 0 else { return }

        let sx = newBounds.width / bounds.width
        let sy = newBounds.height / bounds.height
        bounds = newBounds

        func scale(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * sx, y: point.y * sy)
        }

        for index in polygons.indices {
            polygons[index].points = polygons[index].points.map(scale)
            polygons[index].velocities = polygons[index].velocities.map {
                CGVector(dx: $0.dx * sx, dy: $0.dy * sy)
            }
            polygons[index].trail = polygons[index].trail.map {
                Ghost(points: $0.points.map(scale), hue: $0.hue)
            }
        }
    }

    /// Advances the simulation by `dt` seconds.
    func step(dt: TimeInterval) {
        let area = field
        guard area.width > 0, area.height > 0 else { return }

        timeSinceGhost += dt
        let recordGhost = timeSinceGhost >= Self.ghostInterval
        if recordGhost { timeSinceGhost = 0 }

        for index in polygons.indices {
            var polygon = polygons[index]

            for vertex in polygon.points.indices {
                var point = polygon.points[vertex]
                var velocity = polygon.velocities[vertex]

                point.x += velocity.dx * dt
                point.y += velocity.dy * dt

                if point.x < area.minX {
                    point.x = min(area.minX + (area.minX - point.x), area.maxX)
                    velocity.dx = -velocity.dx
                } else if point.x > area.maxX {
                    point.x = max(area.maxX - (point.x - area.maxX), area.minX)
                    velocity.dx = -velocity.dx
                }

                if point.y < area.minY {
                    point.y = min(area.minY + (area.minY - point.y), area.maxY)
                    velocity.dy = -velocity.dy
                } else if point.y > area.maxY {
                    point.y = max(area.maxY - (point.y - area.maxY), area.minY)
                    velocity.dy = -velocity.dy
                }

                polygon.points[vertex] = point
                polygon.velocities[vertex] = velocity
            }

            polygon.hue = (polygon.hue + polygon.hueSpeed * dt).truncatingRemainder(dividingBy: 1.0)

            if recordGhost, ghostCapacity > 0 {
                polygon.trail.append(Ghost(points: polygon.points, hue: polygon.hue))
                if polygon.trail.count > ghostCapacity {
                    polygon.trail.removeFirst(polygon.trail.count - ghostCapacity)
                }
            }

            polygons[index] = polygon
        }
    }

    /// Draws the current frame. Every ghost is stroked at full brightness —
    /// the original Mystify simply erased the oldest polygon rather than
    /// fading it, and that hard-edged look is the point.
    func draw(in rect: CGRect, context: CGContext) {
        context.setFillColor(NSColor.black.cgColor)
        context.fill(rect)

        context.setLineWidth(settings.lineWidth)
        context.setLineJoin(.round)

        for polygon in polygons {
            // Oldest first so the live shape ends up on top.
            for ghost in polygon.trail {
                stroke(ghost.points, hue: ghost.hue, in: context)
            }
            stroke(polygon.points, hue: polygon.hue, in: context)
        }
    }

    private func stroke(_ points: [CGPoint], hue: Double, in context: CGContext) {
        guard points.count >= 2 else { return }
        let color = NSColor(calibratedHue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
        context.setStrokeColor(color.cgColor)
        context.addLines(between: points)
        context.closePath()
        context.strokePath()
    }

    /// The area vertices bounce inside, inset so strokes stay fully on screen.
    private var field: CGRect {
        bounds.insetBy(dx: settings.lineWidth / 2, dy: settings.lineWidth / 2)
    }
}
