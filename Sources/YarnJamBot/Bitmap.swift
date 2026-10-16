import CoreGraphics
import Foundation

struct Bitmap {
    var width: Int
    var height: Int
    var rgba: [UInt8]

    subscript(x: Int, y: Int) -> RGB {
        let i = (y * width + x) * 4
        return RGB(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
    }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    static func from(_ image: CGImage) -> Bitmap {
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Bitmap(width: width, height: height, rgba: rgba)
    }

    func scaledDown(longestSide: Int) -> (bitmap: Bitmap, scale: CGFloat) {
        let longest = max(width, height)
        if longest <= longestSide {
            return (self, 1)
        }
        let factor = Int((Double(longest) / Double(longestSide)).rounded(.up))
        let newWidth = max(1, width / factor)
        let newHeight = max(1, height / factor)
        var out = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        for y in 0..<newHeight {
            for x in 0..<newWidth {
                let src = ((y * factor) * width + (x * factor)) * 4
                let dst = (y * newWidth + x) * 4
                out[dst] = rgba[src]
                out[dst + 1] = rgba[src + 1]
                out[dst + 2] = rgba[src + 2]
                out[dst + 3] = 255
            }
        }
        return (Bitmap(width: newWidth, height: newHeight, rgba: out), CGFloat(factor))
    }
}

func isBeige(_ c: RGB) -> Bool {
    let r = Int(c.r), g = Int(c.g), b = Int(c.b)
    return r > 165 && g > 135 && b > 95 && r + 15 >= g && g + 20 >= b && (r - b) > 20 && (r - b) < 150
}

func isNavy(_ c: RGB) -> Bool {
    let r = Int(c.r), g = Int(c.g), b = Int(c.b)
    let maxC = max(r, g, b)
    let minC = min(r, g, b)
    return maxC < 78 && b + 18 >= g && g + 24 >= r && (maxC - minC) < 48
}

func isWhite(_ c: RGB) -> Bool {
    let r = Int(c.r), g = Int(c.g), b = Int(c.b)
    return min(r, g, b) > 205 && (max(r, g, b) - min(r, g, b)) < 38
}

func isDarkWood(_ c: RGB) -> Bool {
    let r = Int(c.r), g = Int(c.g), b = Int(c.b)
    return r > 65 && r < 175 && g > 40 && g < 145 && b > 18 && b < 115 && r > g && g > b && (r - b) > 24
}

func makeImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
    let data = Data(rgba) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

extension Bitmap {
    func image() -> CGImage? {
        makeImage(width: width, height: height, rgba: rgba)
    }

    /// Smooth enlargement, so thin ropes on a small board get enough pixels to show an arrowhead.
    func enlarged(by factor: CGFloat) -> Bitmap? {
        guard factor > 1, let source = image() else { return nil }
        let newWidth = Int((CGFloat(width) * factor).rounded())
        let newHeight = Int((CGFloat(height) * factor).rounded())
        var out = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        let drawn: Bool = out.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: newWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            return true
        }
        return drawn ? Bitmap(width: newWidth, height: newHeight, rgba: out) : nil
    }
}

func colorsMatch(_ a: RGB, _ b: RGB) -> Bool {
    if a.saturation < 0.22 || b.saturation < 0.22 {
        return a.saturation < 0.38 && b.saturation < 0.38 && a.distance(to: b) < 58
    }
    return hueDistance(a.hue, b.hue) < 26 && abs(a.saturation - b.saturation) < 0.62
}
