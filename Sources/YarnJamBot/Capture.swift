import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

func loadShot(path: String) throws -> Shot {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw CaptureError.unreadable(path)
    }
    return Shot(image: image, map: nil)
}

func captureDisplays() async throws -> [Shot] {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    var shots: [Shot] = []
    for display in content.displays {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        config.capturesAudio = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let bounds = CGDisplayBounds(display.displayID)
        let map = ScreenMap(
            displayID: display.displayID,
            bounds: bounds,
            captureScale: 1,
            capturePixelWidth: CGFloat(image.width),
            capturePixelHeight: CGFloat(image.height)
        )
        shots.append(Shot(image: image, map: map))
    }
    return shots
}

enum CaptureError: Error, CustomStringConvertible {
    case unreadable(String)
    case empty

    var description: String {
        switch self {
        case .unreadable(let path): return "Could not read image at \(path)"
        case .empty: return "No display was captured"
        }
    }
}
