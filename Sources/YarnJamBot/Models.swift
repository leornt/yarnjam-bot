import CoreGraphics
import Foundation

struct ScreenMap {
    var displayID: CGDirectDisplayID
    var bounds: CGRect
    /// Multiply an analysis pixel by this to get a capture pixel.
    var captureScale: CGFloat

    func globalPoint(analysisX: CGFloat, analysisY: CGFloat) -> CGPoint {
        let captureX = analysisX * captureScale
        let captureY = analysisY * captureScale
        let pointsPerCapturePixelX = bounds.width / max(capturePixelWidth, 1)
        let pointsPerCapturePixelY = bounds.height / max(capturePixelHeight, 1)
        return CGPoint(
            x: bounds.origin.x + captureX * pointsPerCapturePixelX,
            y: bounds.origin.y + captureY * pointsPerCapturePixelY
        )
    }

    var capturePixelWidth: CGFloat
    var capturePixelHeight: CGFloat
}

struct Shot {
    var image: CGImage
    var map: ScreenMap?
}

struct RGB {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    var hue: Float
    var saturation: Float
    var value: Float

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        let rf = Float(r) / 255
        let gf = Float(g) / 255
        let bf = Float(b) / 255
        let maxV = max(rf, gf, bf)
        let minV = min(rf, gf, bf)
        let delta = maxV - minV
        value = maxV
        saturation = maxV == 0 ? 0 : delta / maxV
        if delta == 0 {
            hue = 0
        } else if maxV == rf {
            hue = (gf - bf) / delta
        } else if maxV == gf {
            hue = (bf - rf) / delta + 2
        } else {
            hue = (rf - gf) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
    }

    func distance(to other: RGB) -> Float {
        let dr = Float(Int(r) - Int(other.r))
        let dg = Float(Int(g) - Int(other.g))
        let db = Float(Int(b) - Int(other.b))
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

func hueDistance(_ a: Float, _ b: Float) -> Float {
    var d = abs(a - b)
    if d > 180 { d = 360 - d }
    return d
}

extension RGB {
    var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct SlotReading {
    var center: CGPoint
    var radius: CGFloat
    var filled: Bool
}

struct CouchReading {
    var index: Int
    var rect: CGRect
    var rim: CGRect
    var locked: Bool
    /// Learned from the couch rim on screen, never from a fixed palette.
    var hue: Float
    var color: RGB
    var filledSlots: Int
    var slots: [SlotReading]

    var openSlots: Int { locked ? 0 : max(0, 3 - filledSlots) }
}

struct PegReading {
    var index: Int
    var center: CGPoint
    var radius: CGFloat
    var occupied: Bool
    var hue: Float
}

struct YarnReading {
    var id: Int
    var hue: Float
    var alternateHue: Float?
    var saturation: Float
    var value: Float
    var average: RGB
    var roundEnd: CGPoint
    var arrowTip: CGPoint
    var direction: CGVector
    var clickPoint: CGPoint
    var free: Bool
    var resolved: Bool
    /// Rope component IDs found in the forward corridor, nearest first.
    var blockingYarnIDs: [Int]
    /// Rope width across the body, in analysis pixels. Zero when unresolved.
    var thickness: CGFloat
}

enum TargetReason: String {
    case couch
    case buffer
}

struct YarnTarget {
    var yarn: YarnReading
    var reason: TargetReason
    var couchIndex: Int?

    var label: String {
        if reason == .couch, let couchIndex {
            return "matches couch \(couchIndex)"
        }
        if let couchIndex {
            return "for a buffer peg; unblocks couch \(couchIndex)"
        }
        return "for a buffer peg"
    }
}

struct BoardReading {
    var map: ScreenMap?
    var tray: CGRect
    var field: CGRect
    var couches: [CouchReading]
    var pegs: [PegReading]
    var yarns: [YarnReading]
    var targets: [YarnTarget]
    /// Analysis-space image the overlay draws on top of.
    var image: CGImage
}

extension CGPoint {
    func offset(by vector: CGVector, times t: CGFloat) -> CGPoint {
        CGPoint(x: x + vector.dx * t, y: y + vector.dy * t)
    }
}
