import CoreGraphics
import CoreText
import Foundation
import ImageIO

func writeOverlay(_ board: BoardReading, to path: String) {
    let image = board.image
    let width = image.width
    let height = image.height
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    func up(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGFloat(height) - point.y)
    }
    func up(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
    }

    func stroke(_ rect: CGRect, color: CGColor, width: CGFloat) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.stroke(rect)
    }

    stroke(up(board.field), color: CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1), width: 2)
    for couch in board.couches {
        let color: CGColor = couch.locked
            ? CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            : CGColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
        stroke(up(couch.rect), color: color, width: 2)
        guard !couch.locked else { continue }
        stroke(up(couch.rim), color: CGColor(red: 1, green: 0.4, blue: 1, alpha: 1), width: 1)
        for slot in couch.slots {
            let center = up(slot.center)
            let rect = CGRect(
                x: center.x - slot.radius,
                y: center.y - slot.radius,
                width: slot.radius * 2,
                height: slot.radius * 2
            )
            let slotColor: CGColor = slot.filled
                ? CGColor(red: 0.2, green: 1, blue: 0.3, alpha: 1)
                : CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
            context.setStrokeColor(slotColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: rect)
        }
    }
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(2)
    for peg in board.pegs {
        let center = up(peg.center)
        let rect = CGRect(
            x: center.x - peg.radius,
            y: center.y - peg.radius,
            width: peg.radius * 2,
            height: peg.radius * 2
        )
        context.strokeEllipse(in: rect)
    }

    for yarn in board.yarns where yarn.resolved {
        let color: CGColor = yarn.free
            ? CGColor(red: 0.3, green: 1, blue: 0.4, alpha: 1)
            : CGColor(red: 1, green: 0.35, blue: 0.3, alpha: 0.9)
        context.setStrokeColor(color)
        context.setLineWidth(2)
        let tip = up(yarn.arrowTip)
        context.move(to: tip)
        let far = tip.offset(by: CGVector(dx: yarn.direction.dx, dy: -yarn.direction.dy), times: 18)
        context.addLine(to: far)
        context.strokePath()
    }

    for (index, target) in board.targets.enumerated() {
        let point = up(target.yarn.clickPoint)
        let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0.2, alpha: 1))
        context.fillEllipse(in: rect)
        drawLabel("\(index + 1)", at: CGPoint(x: point.x + 8, y: point.y + 4), in: context)
    }

    guard let out = context.makeImage() else { return }
    writeCGImage(out, to: path)
}

func writeCGImage(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

private func drawLabel(_ text: String, at point: CGPoint, in context: CGContext) {
    let font = CTFontCreateWithName("Menlo" as CFString, 12, nil)
    let color = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let attr = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
    CFAttributedStringReplaceString(attr, CFRangeMake(0, 0), text as CFString)
    let range = CFRangeMake(0, text.utf16.count)
    CFAttributedStringSetAttribute(attr, range, kCTFontAttributeName, font)
    CFAttributedStringSetAttribute(attr, range, kCTForegroundColorAttributeName, color)
    let line = CTLineCreateWithAttributedString(attr)
    context.textPosition = point
    CTLineDraw(line, context)
}
