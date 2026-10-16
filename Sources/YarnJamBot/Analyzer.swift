import CoreGraphics
import Dispatch
import Foundation

struct Layout {
    var tray: CGRect
    var field: CGRect
    var couches: [CouchReading]
    var pegs: [PegReading]
    var pegRadius: CGFloat
}

/// Smaller boards are enlarged to this peg radius before reading. Below it an arrowhead is only a pixel or two wider than its rope.
private let minimumPegRadius: CGFloat = 16

struct Analyzer {
    func locate(in bitmap: Bitmap) -> Layout? {
        guard let band = bestBeigeBand(bitmap) else { return nil }
        let trayX = beigeSpan(bitmap, y0: band.0, y1: band.1)
        guard trayX.maxX - trayX.minX > 80 else { return nil }
        let tray = CGRect(
            x: trayX.minX,
            y: CGFloat(band.0),
            width: trayX.maxX - trayX.minX,
            height: CGFloat(band.1 - band.0)
        )
        let pegs = findPegs(bitmap, tray: tray)
        guard pegs.count == 5 else { return nil }
        let radius = pegs.map(\.radius).reduce(0, +) / CGFloat(pegs.count)
        guard let field = findField(bitmap, tray: tray, pegs: pegs) else { return nil }
        let couches = findCouches(bitmap, tray: tray)
        guard couches.count == 4 else { return nil }
        return Layout(tray: tray, field: field, couches: couches, pegs: pegs, pegRadius: radius)
    }

    func read(shot: Shot) -> BoardReading? {
        let source = Bitmap.from(shot.image)
        var (bitmap, scale) = source.scaledDown(longestSide: 2000)
        guard var layout = locate(in: bitmap) else { return nil }
        let growth = minimumPegRadius / layout.pegRadius
        if growth > 1.15, let larger = bitmap.enlarged(by: growth), let relocated = locate(in: larger) {
            scale *= CGFloat(bitmap.width) / CGFloat(larger.width)
            bitmap = larger
            layout = relocated
        }
        guard let image = bitmap.image() else { return nil }
        let yarns = findYarns(bitmap, layout: layout)
        let targets = pickTargets(yarns: yarns, couches: layout.couches, pegs: layout.pegs)
        var map = shot.map
        if var adjusted = map {
            adjusted.captureScale = scale
            map = adjusted
        }
        return BoardReading(
            map: map,
            tray: layout.tray,
            field: layout.field,
            couches: layout.couches,
            pegs: layout.pegs,
            yarns: yarns,
            targets: targets,
            image: image
        )
    }
}

// MARK: - Tray, pegs, couches

private struct BeigeSpan {
    var x0: Int
    var x1: Int
    var count: Int
}

/// Widest beige run on one row. Small gaps stay inside the run so couch seats do not split the tray.
private func widestBeigeSpan(_ bitmap: Bitmap, y: Int) -> BeigeSpan? {
    var best: BeigeSpan?
    var x = 0
    while x < bitmap.width {
        if !isBeige(bitmap[x, y]) {
            x += 1
            continue
        }
        let x0 = x
        var count = 0
        var gap = 0
        var last = x
        while x < bitmap.width {
            if isBeige(bitmap[x, y]) {
                count += 1
                last = x
                gap = 0
                x += 1
            } else {
                gap += 1
                if gap > 80 { break }
                x += 1
            }
        }
        let span = BeigeSpan(x0: x0, x1: last, count: count)
        let width = span.x1 - span.x0
        if width > 90, count > width / 3, best == nil || width > (best!.x1 - best!.x0) {
            best = span
        }
    }
    return best
}

private func bestBeigeBand(_ bitmap: Bitmap) -> (Int, Int)? {
    var bands: [(Int, Int)] = []
    var start: Int?
    var gap = 0
    for y in 0..<bitmap.height {
        if widestBeigeSpan(bitmap, y: y) != nil {
            if start == nil { start = y }
            gap = 0
        } else if let s = start {
            gap += 1
            if gap > 14 {
                bands.append((s, y - gap))
                start = nil
                gap = 0
            }
        }
    }
    if let s = start {
        bands.append((s, max(s, bitmap.height - 1 - gap)))
    }

    var best: (Int, Int, Double)?
    for band in bands {
        let height = band.1 - band.0
        guard height > 36, height < bitmap.height / 2 else { continue }
        let span = beigeSpan(bitmap, y0: band.0, y1: band.1)
        let width = span.maxX - span.minX
        guard width > 80 else { continue }
        let tray = CGRect(x: span.minX, y: CGFloat(band.0), width: width, height: CGFloat(height))
        let pegs = findPegs(bitmap, tray: tray)
        guard pegs.count == 5 else { continue }
        let navyRatio = navyBelow(bitmap, tray: tray)
        guard navyRatio > 0.25 else { continue }
        let score = navyRatio * 10 + width
        if best == nil || score > best!.2 {
            best = (band.0, band.1, score)
        }
    }
    guard let best else { return nil }
    return (best.0, best.1)
}

private func navyBelow(_ bitmap: Bitmap, tray: CGRect) -> Double {
    let y0 = min(bitmap.height - 1, Int(tray.maxY) + 8)
    let y1 = min(bitmap.height - 1, y0 + Int(tray.height))
    guard y1 > y0 else { return 0 }
    let x0 = max(0, Int(tray.minX))
    let x1 = min(bitmap.width - 1, Int(tray.maxX))
    var navy = 0
    var samples = 0
    for y in y0...y1 {
        var x = x0
        while x <= x1 {
            if isNavy(bitmap[x, y]) { navy += 1 }
            samples += 1
            x += 3
        }
    }
    return Double(navy) / Double(max(samples, 1))
}

private func beigeSpan(_ bitmap: Bitmap, y0: Int, y1: Int) -> (minX: CGFloat, maxX: CGFloat) {
    let y = min(bitmap.height - 1, max(0, (y0 + y1) / 2))
    var minX = bitmap.width
    var maxX = 0
    var run = 0
    for x in 0..<bitmap.width {
        if isBeige(bitmap[x, y]) {
            run += 1
            if run > 6 {
                minX = min(minX, x - run)
                maxX = max(maxX, x)
            }
        } else {
            run = 0
        }
    }
    if maxX <= minX {
        return (0, CGFloat(bitmap.width))
    }
    return (CGFloat(max(0, minX)), CGFloat(min(bitmap.width - 1, maxX)))
}

private struct Blob {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
    var area: Int
    var sumX: Int
    var sumY: Int

    var center: CGPoint {
        CGPoint(x: CGFloat(sumX) / CGFloat(area), y: CGFloat(sumY) / CGFloat(area))
    }

    var radius: CGFloat {
        CGFloat(maxX - minX + maxY - minY) / 4
    }
}

private func findPegs(_ bitmap: Bitmap, tray: CGRect) -> [PegReading] {
    let y0 = max(0, Int(tray.maxY) - 6)
    let y1 = min(bitmap.height - 1, Int(tray.maxY) + Int(tray.height * 0.95) + 30)
    let x0 = max(0, Int(tray.minX) - 8)
    let x1 = min(bitmap.width - 1, Int(tray.maxX) + 8)
    guard y1 > y0, x1 > x0 else { return [] }

    var seen = [UInt8](repeating: 0, count: bitmap.width * bitmap.height)
    var blobs: [Blob] = []
    let minArea = max(12, Int(tray.height * tray.height * 0.004))
    let maxArea = Int(tray.height * tray.height * 0.18)

    for y in y0...y1 {
        for x in x0...x1 {
            let index = y * bitmap.width + x
            if seen[index] != 0 || !isWhite(bitmap[x, y]) { continue }
            var blob = Blob(minX: x, minY: y, maxX: x, maxY: y, area: 0, sumX: 0, sumY: 0)
            var stack = [(x, y)]
            seen[index] = 1
            while let (cx, cy) = stack.popLast() {
                blob.area += 1
                blob.sumX += cx
                blob.sumY += cy
                blob.minX = min(blob.minX, cx)
                blob.maxX = max(blob.maxX, cx)
                blob.minY = min(blob.minY, cy)
                blob.maxY = max(blob.maxY, cy)
                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] {
                    guard nx >= x0, nx <= x1, ny >= y0, ny <= y1 else { continue }
                    let ni = ny * bitmap.width + nx
                    if seen[ni] != 0 || !isWhite(bitmap[nx, ny]) { continue }
                    seen[ni] = 1
                    stack.append((nx, ny))
                }
            }
            let bw = blob.maxX - blob.minX + 1
            let bh = blob.maxY - blob.minY + 1
            let aspect = CGFloat(bw) / CGFloat(max(bh, 1))
            let fill = CGFloat(blob.area) / CGFloat(max(bw * bh, 1))
            // A yarn on a peg leaves a short white cap, wider than the cone.
            guard blob.area >= minArea, blob.area <= maxArea, aspect > 0.55, aspect < 2.6, fill > 0.45 else {
                continue
            }
            blobs.append(blob)
        }
    }

    let ordered = collapseStacked(blobs.sorted { $0.center.x < $1.center.x })
    if let pegs = selectPegRow(bitmap, ordered) { return pegs }
    guard let covered = coveredPeg(bitmap, columns: ordered) else { return [] }
    var withCovered = ordered
    withCovered.append(covered)
    withCovered.sort { $0.center.x < $1.center.x }
    return selectPegRow(bitmap, withCovered) ?? []
}

private struct PegRowMetrics {
    var spacing: CGFloat
    var std: CGFloat
    var meanY: CGFloat
    var meanR: CGFloat
    var ySpan: CGFloat
}

/// Evenly spaced pegs on one horizontal line.
private func pegRowMetrics(_ group: [Blob]) -> PegRowMetrics? {
    guard group.count >= 2 else { return nil }
    let ys = group.map(\.center.y)
    let ySpan = (ys.max() ?? 0) - (ys.min() ?? 0)
    let radii = group.map(\.radius)
    let meanR = radii.reduce(0, +) / CGFloat(group.count)
    guard meanR > 4, ySpan < meanR * 2.2 else { return nil }
    var spacings: [CGFloat] = []
    for index in 0..<(group.count - 1) {
        spacings.append(group[index + 1].center.x - group[index].center.x)
    }
    let meanS = spacings.reduce(0, +) / CGFloat(spacings.count)
    guard meanS > meanR * 1.4 else { return nil }
    let variance = spacings.reduce(0) { $0 + ($1 - meanS) * ($1 - meanS) } / CGFloat(spacings.count)
    let std = variance.squareRoot()
    guard std / meanS < 0.22 else { return nil }
    let radiusSpread = (radii.max() ?? 0) - (radii.min() ?? 0)
    guard radiusSpread < meanR * 0.8 else { return nil }
    let meanY = ys.reduce(0, +) / CGFloat(ys.count)
    return PegRowMetrics(spacing: meanS, std: std, meanY: meanY, meanR: meanR, ySpan: ySpan)
}

private func selectPegRow(_ bitmap: Bitmap, _ ordered: [Blob]) -> [PegReading]? {
    guard ordered.count >= 5 else { return nil }
    var best: (score: CGFloat, pegs: [PegReading])?
    for i in 0...(ordered.count - 5) {
        let group = Array(ordered[i..<(i + 5)])
        guard let metrics = pegRowMetrics(group) else { continue }
        let score = metrics.spacing / (1 + metrics.std) - metrics.ySpan
        if best == nil || score > best!.score {
            let pegs = group.enumerated().map { offset, blob in
                occupiedPeg(bitmap, blob: blob, index: offset + 1)
            }
            best = (score, pegs)
        }
    }
    return best?.pegs
}

/// A yarn can hide a peg completely. The missing spot is one spacing outside an even row of four, where the yarn color sits.
private func coveredPeg(_ bitmap: Bitmap, columns: [Blob]) -> Blob? {
    guard columns.count >= 4 else { return nil }
    var best: Blob?
    var bestArea = 0
    for i in 0...(columns.count - 4) {
        let group = Array(columns[i..<(i + 4)])
        guard let metrics = pegRowMetrics(group) else { continue }
        let sides = [
            group[0].center.x - metrics.spacing,
            group[3].center.x + metrics.spacing,
        ]
        for x in sides {
            guard let blob = yarnBlob(bitmap, x: x, y: metrics.meanY, radius: metrics.meanR) else { continue }
            if blob.area > bestArea {
                bestArea = blob.area
                best = blob
            }
        }
    }
    return best
}

/// Yarn color in the circle where a hidden peg would be. The box is the yarn, so occupancy is read from it.
private func yarnBlob(_ bitmap: Bitmap, x: CGFloat, y: CGFloat, radius: CGFloat) -> Blob? {
    let cx = Int(x.rounded())
    let cy = Int(y.rounded())
    let r = max(4, Int(radius * 1.3))
    var blob = Blob(minX: cx, minY: cy, maxX: cx, maxY: cy, area: 0, sumX: 0, sumY: 0)
    var samples = 0
    for py in (cy - r)...(cy + r) {
        for px in (cx - r)...(cx + r) {
            let dx = px - cx, dy = py - cy
            if dx * dx + dy * dy > r * r { continue }
            guard bitmap.contains(px, py) else { continue }
            samples += 1
            guard isYarnOnPeg(bitmap[px, py]) else { continue }
            if blob.area == 0 {
                blob.minX = px
                blob.maxX = px
                blob.minY = py
                blob.maxY = py
            }
            blob.area += 1
            blob.sumX += px
            blob.sumY += py
            blob.minX = min(blob.minX, px)
            blob.maxX = max(blob.maxX, px)
            blob.minY = min(blob.minY, py)
            blob.maxY = max(blob.maxY, py)
        }
    }
    guard samples > 0, blob.area * 4 > samples else { return nil }
    return blob
}

private func isYarnOnPeg(_ c: RGB) -> Bool {
    c.saturation > 0.45 && c.value > 0.40 && !isBeige(c)
}

private func collapseStacked(_ blobs: [Blob]) -> [Blob] {
    var columns: [Blob] = []
    for blob in blobs {
        if let last = columns.last {
            let reach = max(blob.radius, last.radius)
            let sameColumn = abs(blob.center.x - last.center.x) < reach
            let stacked = abs(blob.center.y - last.center.y) < reach * 2.4
            if sameColumn && stacked {
                if blob.area > last.area { columns[columns.count - 1] = blob }
                continue
            }
        }
        columns.append(blob)
    }
    return columns
}

private func occupiedPeg(_ bitmap: Bitmap, blob: Blob, index: Int) -> PegReading {
    let cx = Int(blob.center.x.rounded())
    // The yarn covers the cone from the bottom up and leaves the white cap above it.
    let cy = blob.maxY
    let r = max(3, Int(max(blob.radius, 4) * 0.95))
    var sumR = 0, sumG = 0, sumB = 0, yarn = 0, samples = 0
    for y in (cy - r)...(cy + r) {
        for x in (cx - r)...(cx + r) {
            let dx = x - cx, dy = y - cy
            if dx * dx + dy * dy > r * r { continue }
            guard bitmap.contains(x, y) else { continue }
            samples += 1
            let c = bitmap[x, y]
            guard isYarnOnPeg(c) else { continue }
            sumR += Int(c.r)
            sumG += Int(c.g)
            sumB += Int(c.b)
            yarn += 1
        }
    }
    let occupied = samples > 0 && yarn * 5 > samples
    let color = yarn == 0
        ? RGB(r: 255, g: 255, b: 255)
        : RGB(r: UInt8(sumR / yarn), g: UInt8(sumG / yarn), b: UInt8(sumB / yarn))
    return PegReading(
        index: index,
        center: blob.center,
        radius: blob.radius,
        occupied: occupied,
        hue: color.hue
    )
}

private func findField(_ bitmap: Bitmap, tray: CGRect, pegs: [PegReading]) -> CGRect? {
    let top = Int((pegs.map { $0.center.y + $0.radius }.max() ?? tray.maxY) + 4)
    guard top < bitmap.height - 10 else { return nil }
    let x0 = Int(tray.minX)
    let x1 = Int(tray.maxX)
    var bottom = top
    var dull = 0
    for y in top..<bitmap.height {
        var navy = 0, samples = 0
        var x = x0
        while x <= x1 {
            if bitmap.contains(x, y), isNavy(bitmap[x, y]) { navy += 1 }
            samples += 1
            x += 2
        }
        let ratio = Double(navy) / Double(max(samples, 1))
        if ratio > 0.18 {
            bottom = y
            dull = 0
        } else {
            dull += 1
            if dull > 18 { break }
        }
    }
    guard bottom - top > 40 else { return nil }
    return CGRect(x: tray.minX, y: CGFloat(top), width: tray.width, height: CGFloat(bottom - top))
}

private func findCouches(_ bitmap: Bitmap, tray: CGRect) -> [CouchReading] {
    let cells = couchCells(bitmap, tray: tray)
    return cells.enumerated().map { offset, rect in
        readCouch(bitmap, rect: rect, index: offset + 1)
    }
}

private func couchCells(_ bitmap: Bitmap, tray: CGRect) -> [CGRect] {
    let y0 = Int(tray.minY)
    let y1 = min(bitmap.height - 1, Int(tray.maxY))
    let x0 = Int(tray.minX)
    let x1 = min(bitmap.width - 1, Int(tray.maxX))
    var score = [Int](repeating: 0, count: bitmap.width)
    for y in stride(from: y0, through: y1, by: 1) {
        for x in x0...x1 where isDarkWood(bitmap[x, y]) {
            score[x] += 1
        }
    }
    let need = max(8, Int(Double(tray.height) * 0.42))
    var runs: [(Int, Int)] = []
    var runStart: Int?
    for x in x0...x1 {
        if score[x] >= need {
            if runStart == nil { runStart = x }
        } else if let s = runStart {
            runs.append((s, x - 1))
            runStart = nil
        }
    }
    if let s = runStart { runs.append((s, x1)) }

    var posts: [CGFloat] = []
    for run in runs {
        let center = CGFloat(run.0 + run.1) / 2
        if let last = posts.last, center - last < 24 {
            posts[posts.count - 1] = (last + center) / 2
        } else {
            posts.append(center)
        }
    }

    if posts.count == 5 {
        return (0..<4).map { i in
            let left = posts[i] + 3
            let right = posts[i + 1] - 3
            return CGRect(x: left, y: tray.minY, width: max(8, right - left), height: tray.height)
        }
    }

    let inner = tray.insetBy(dx: tray.width * 0.02, dy: 0)
    let slot = inner.width / 4
    return (0..<4).map { i in
        CGRect(x: inner.minX + CGFloat(i) * slot, y: inner.minY, width: slot, height: inner.height)
    }
}

/// Slot centers as fractions of the rim box (x across, y down), and the sample radius as a fraction of rim width.
private let slotCenters: [(CGFloat, CGFloat)] = [(0.31, 0.30), (0.67, 0.34), (0.52, 0.62)]
private let slotRadius: CGFloat = 0.15
/// Rim height over rim width. The rim is measured from its bottom and sides, because the handle can merge into its top.
private let rimAspect: CGFloat = 0.947

private func isPaint(_ c: RGB) -> Bool {
    c.saturation > 0.45 && c.value > 0.28
}

/// Dusty pink sits below the saturated-rim cut and above the cream seat.
private func isPastelPaint(_ c: RGB) -> Bool {
    guard c.saturation > 0.20, c.saturation <= 0.45, c.value > 0.45 else { return false }
    let wood = c.hue > 25 && c.hue < 55
    return !wood
}

/// A white rim has no usable hue. It is bright and nearly gray, unlike the warm cream seat.
private func isWhitePaint(_ c: RGB) -> Bool {
    c.saturation < 0.10 && c.value > 0.80
}

/// A black or charcoal rim is nearly gray. It is darker than the cream seat and lighter than a hole.
private func isDarkPaint(_ c: RGB) -> Bool {
    let r = Int(c.r), g = Int(c.g), b = Int(c.b)
    let maxC = max(r, g, b)
    let minC = min(r, g, b)
    return maxC > 32 && maxC < 85 && (maxC - minC) < 28 && !isBeige(c)
}

private struct RimReading {
    var box: CGRect
    var mean: RGB
    var hue: Float
}

/// The rim is the largest connected region of one hue that is wide and tall within the bay.
/// Full-height columns are the tray's wooden bars, so they are cleared before the search.
private func findRim(_ bitmap: Bitmap, rect: CGRect) -> RimReading? {
    let x0 = max(0, Int(rect.minX))
    let x1 = min(bitmap.width - 1, Int(rect.maxX))
    let y0 = max(0, Int(rect.minY))
    let y1 = min(bitmap.height - 1, Int(rect.maxY))
    guard x1 > x0 + 8, y1 > y0 + 8 else { return nil }
    let w = x1 - x0 + 1
    let h = y1 - y0 + 1

    var paint = [Bool](repeating: false, count: w * h)
    var pastel = [Bool](repeating: false, count: w * h)
    var dark = [Bool](repeating: false, count: w * h)
    var hues = [Float](repeating: 0, count: w * h)
    var white = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let c = bitmap[x0 + x, y0 + y]
            hues[y * w + x] = c.hue
            if isPaint(c) { paint[y * w + x] = true }
            if isPastelPaint(c) { pastel[y * w + x] = true }
            if isDarkPaint(c) { dark[y * w + x] = true }
            if isWhitePaint(c) { white[y * w + x] = true }
        }
    }
    for x in 0..<w {
        var paintCount = 0
        var darkCount = 0
        for y in 0..<h {
            if paint[y * w + x] { paintCount += 1 }
            if dark[y * w + x] { darkCount += 1 }
        }
        if Double(paintCount) >= Double(h) * 0.8 {
            for y in 0..<h { paint[y * w + x] = false }
        }
        if Double(darkCount) >= Double(h) * 0.8 {
            for y in 0..<h { dark[y * w + x] = false }
        }
    }

    let colored = largestRim(paint, hues: hues, w: w, h: h, x0: x0, y0: y0, gateHue: true)
        ?? largestRim(pastel, hues: hues, w: w, h: h, x0: x0, y0: y0, gateHue: true)
        ?? largestRim(dark, hues: hues, w: w, h: h, x0: x0, y0: y0, gateHue: false)
    // White is the couch only when the bay has no colored rim. A locked bay has a green plus
    // and no colored rim, so its pale border is not a white couch.
    let best = colored ?? (bayHasLockPlus(bitmap, x0: x0, y0: y0, w: w, h: h)
        ? nil
        : largestRim(white, hues: hues, w: w, h: h, x0: x0, y0: y0, gateHue: false))
    guard let best else { return nil }

    var bins = [Int](repeating: 0, count: 36)
    var sums = [Float](repeating: 0, count: 36)
    for i in best.pixels {
        let bin = min(35, Int(hues[i] / 10))
        bins[bin] += 1
        sums[bin] += hues[i]
    }
    let peak = bins.enumerated().max { $0.element < $1.element }!.offset
    let hue = circularBinHue(bins: bins, sums: sums, peak: peak) ?? 0

    var r = 0, g = 0, b = 0, n = 0
    for i in best.pixels where hueDistance(hues[i], hue) < 15 {
        let c = bitmap[x0 + i % w, y0 + i / w]
        r += Int(c.r)
        g += Int(c.g)
        b += Int(c.b)
        n += 1
    }
    if n == 0 {
        for i in best.pixels {
            let c = bitmap[x0 + i % w, y0 + i / w]
            r += Int(c.r)
            g += Int(c.g)
            b += Int(c.b)
            n += 1
        }
    }
    n = max(n, 1)
    let mean = RGB(r: UInt8(r / n), g: UInt8(g / n), b: UInt8(b / n))
    return RimReading(box: best.box, mean: mean, hue: hue)
}

/// Mean hue of a 10-degree bin and its two neighbors. Red sits on both sides of 0/360,
/// so a neighbor across the wrap is shifted by a full turn before averaging.
private func circularBinHue(bins: [Int], sums: [Float], peak: Int) -> Float? {
    var count = 0
    var sum: Float = 0
    for offset in -1...1 {
        let raw = peak + offset
        let bin = (raw + 36) % 36
        let shift: Float = raw < 0 ? -360 : (raw > 35 ? 360 : 0)
        count += bins[bin]
        sum += sums[bin] + shift * Float(bins[bin])
    }
    guard count > 0 else { return nil }
    var hue = sum / Float(count)
    if hue < 0 { hue += 360 }
    if hue >= 360 { hue -= 360 }
    return hue
}

/// The locked couches carry a green plus on the cream seat. A playable couch does not.
private func bayHasLockPlus(_ bitmap: Bitmap, x0: Int, y0: Int, w: Int, h: Int) -> Bool {
    let cx = w / 2
    let cy = h / 2
    let rx = max(8, w / 5)
    let ry = max(8, h / 5)
    var count = 0
    for y in max(0, cy - ry)...min(h - 1, cy + ry) {
        for x in max(0, cx - rx)...min(w - 1, cx + rx) {
            let c = bitmap[x0 + x, y0 + y]
            if c.saturation > 0.45, c.value > 0.45, c.hue > 70, c.hue < 150 {
                count += 1
            }
        }
    }
    return count > 40
}

private func largestRim(
    _ mask: [Bool],
    hues: [Float],
    w: Int,
    h: Int,
    x0: Int,
    y0: Int,
    gateHue: Bool
) -> (area: Int, box: CGRect, pixels: [Int])? {
    var seen = [Bool](repeating: false, count: w * h)
    var best: (area: Int, box: CGRect, pixels: [Int])?
    for start in 0..<(w * h) where mask[start] && !seen[start] {
        var stack = [start]
        var pixels: [Int] = []
        seen[start] = true
        var minX = w, minY = h, maxX = 0, maxY = 0
        while let i = stack.popLast() {
            pixels.append(i)
            let x = i % w
            let y = i / w
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let n = ny * w + nx
                if !mask[n] || seen[n] { continue }
                if gateHue && hueDistance(hues[n], hues[i]) >= 20 { continue }
                seen[n] = true
                stack.append(n)
            }
        }
        let bw = maxX - minX
        let bh = maxY - minY
        guard Double(bw) >= Double(w) * 0.5, Double(bh) >= Double(h) * 0.35 else { continue }
        if best == nil || pixels.count > best!.area {
            let width = CGFloat(bw)
            let height = width * rimAspect
            let box = CGRect(
                x: CGFloat(x0 + minX),
                y: CGFloat(y0 + maxY) - height,
                width: width,
                height: height
            )
            best = (pixels.count, box, pixels)
        }
    }
    return best
}

private func readCouch(_ bitmap: Bitmap, rect: CGRect, index: Int) -> CouchReading {
    guard let rim = findRim(bitmap, rect: rect) else {
        return CouchReading(
            index: index,
            rect: rect,
            rim: .null,
            locked: true,
            hue: 0,
            color: RGB(r: 0, g: 0, b: 0),
            filledSlots: 0,
            slots: []
        )
    }
    let slots = readSlots(bitmap, rim: rim)
    return CouchReading(
        index: index,
        rect: rect,
        rim: rim.box,
        locked: false,
        hue: rim.hue,
        color: rim.mean,
        filledSlots: slots.filter(\.filled).count,
        slots: slots
    )
}

/// A slot is filled when a ball of the couch's own color covers it. An empty slot shows a pale peg.
private func readSlots(_ bitmap: Bitmap, rim: RimReading) -> [SlotReading] {
    let radius = max(3, rim.box.width * slotRadius)
    return slotCenters.map { fx, fy in
        let center = CGPoint(x: rim.box.minX + rim.box.width * fx, y: rim.box.minY + rim.box.height * fy)
        var match = 0
        var total = 0
        let r = Int(radius)
        let cx = Int(center.x)
        let cy = Int(center.y)
        for y in (cy - r)...(cy + r) {
            for x in (cx - r)...(cx + r) {
                guard bitmap.contains(x, y) else { continue }
                let dx = x - cx
                let dy = y - cy
                if dx * dx + dy * dy > r * r { continue }
                total += 1
                let c = bitmap[x, y]
                let satFloor = max(0.12, rim.mean.saturation - 0.15)
                if c.saturation > satFloor && c.value > 0.25 && hueDistance(c.hue, rim.hue) < 22 {
                    match += 1
                }
            }
        }
        let share = Double(match) / Double(max(total, 1))
        return SlotReading(center: center, radius: radius, filled: share > 0.2)
    }
}

// MARK: - Yarns

private struct Rope {
    var id: Int
    var area: Int
    var sumR: Int
    var sumG: Int
    var sumB: Int
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
    var hueBins: [Int]
    var hueSums: [Float]

    var mean: RGB {
        let n = max(area, 1)
        return RGB(r: UInt8(sumR / n), g: UInt8(sumG / n), b: UInt8(sumB / n))
    }

    var dominantHue: Float { huePeaks().0 }

    /// A second hue when the rope is clearly two-toned, so a shaded teal can still match its couch.
    var alternateHue: Float? { huePeaks().1 }

    private func huePeaks() -> (Float, Float?) {
        let ranked = hueBins.enumerated().sorted { $0.element > $1.element }
        guard let peak = ranked.first, peak.element > 0 else { return (mean.hue, nil) }
        let primary = averagedHue(around: peak.offset)
        guard ranked.count > 1, ranked[1].element > peak.element / 3 else { return (primary, nil) }
        let secondary = averagedHue(around: ranked[1].offset)
        if hueDistance(primary, secondary) < 18 { return (primary, nil) }
        return (primary, secondary)
    }

    private func averagedHue(around peak: Int) -> Float {
        circularBinHue(bins: hueBins, sums: hueSums, peak: peak) ?? mean.hue
    }
}

private func findYarns(_ bitmap: Bitmap, layout: Layout) -> [YarnReading] {
    let field = layout.field
    let x0 = max(0, Int(field.minX))
    let x1 = min(bitmap.width - 1, Int(field.maxX))
    let y0 = max(0, Int(field.minY))
    let y1 = min(bitmap.height - 1, Int(field.maxY))
    guard x1 > x0, y1 > y0 else { return [] }

    var bgR = 0, bgG = 0, bgB = 0, bgN = 0
    for y in stride(from: y0, through: y1, by: 3) {
        for x in stride(from: x0, through: x1, by: 3) {
            let c = bitmap[x, y]
            if isNavy(c) {
                bgR += Int(c.r)
                bgG += Int(c.g)
                bgB += Int(c.b)
                bgN += 1
            }
        }
    }
    if bgN == 0 { return [] }
    let background = (bgR / bgN, bgG / bgN, bgB / bgN)
    let limit = 44 * 44

    let count = bitmap.width * bitmap.height
    var mask = [UInt8](repeating: 0, count: count)
    for y in y0...y1 {
        for x in x0...x1 {
            let c = bitmap[x, y]
            let dr = Int(c.r) - background.0
            let dg = Int(c.g) - background.1
            let db = Int(c.b) - background.2
            if dr * dr + dg * dg + db * db > limit {
                mask[y * bitmap.width + x] = 1
            }
        }
    }

    var labels = [Int32](repeating: 0, count: count)
    var ropes: [Rope] = []
    var nextID: Int32 = 1
    let minArea = max(36, Int(layout.pegRadius * layout.pegRadius * 0.45))

    for y in y0...y1 {
        for x in x0...x1 {
            let start = y * bitmap.width + x
            if mask[start] == 0 || labels[start] != 0 { continue }
            let id = nextID
            nextID += 1
            var rope = Rope(
                id: Int(id), area: 0, sumR: 0, sumG: 0, sumB: 0,
                minX: x, minY: y, maxX: x, maxY: y,
                hueBins: Array(repeating: 0, count: 36),
                hueSums: Array(repeating: 0, count: 36)
            )
            var queue = [start]
            var head = 0
            labels[start] = id
            while head < queue.count {
                let index = queue[head]
                head += 1
                let cx = index % bitmap.width
                let cy = index / bitmap.width
                let color = bitmap[cx, cy]
                rope.area += 1
                rope.sumR += Int(color.r)
                rope.sumG += Int(color.g)
                rope.sumB += Int(color.b)
                if color.saturation > 0.28 {
                    let bin = min(35, Int(color.hue / 10))
                    rope.hueBins[bin] += 1
                    rope.hueSums[bin] += color.hue
                }
                rope.minX = min(rope.minX, cx)
                rope.maxX = max(rope.maxX, cx)
                rope.minY = min(rope.minY, cy)
                rope.maxY = max(rope.maxY, cy)
                for ny in (cy - 1)...(cy + 1) {
                    for nx in (cx - 1)...(cx + 1) {
                        if nx == cx && ny == cy { continue }
                        guard nx >= x0, nx <= x1, ny >= y0, ny <= y1 else { continue }
                        let ni = ny * bitmap.width + nx
                        if mask[ni] == 0 || labels[ni] != 0 { continue }
                        if sameRope(bitmap[nx, ny], color) {
                            labels[ni] = id
                            queue.append(ni)
                        }
                    }
                }
            }
            let spanX = rope.maxX - rope.minX
            let spanY = rope.maxY - rope.minY
            let span = max(spanX, spanY)
            let narrow = max(1, min(spanX, spanY))
            let centerX = CGFloat(rope.minX + rope.maxX) / 2
            let centerY = CGFloat(rope.minY + rope.maxY) / 2
            let cornerBand = field.minY + max(40, layout.pegRadius * 3.5)
            let side = field.width * 0.14
            let topCorner = centerY < cornerBand && (centerX < field.minX + side || centerX > field.maxX - side)
            let cut = rope.minX <= x0 + 1 || rope.maxX >= x1 - 2 || rope.minY <= y0 + 1 || rope.maxY >= y1 - 2
            // A short yarn is still longer than it is thick. Only a small piece that is short in both
            // directions is discarded (the level pill, the mute button). A long yarn can fold into a
            // square bounding box, so this shape test does not apply to large pieces.
            let longEnough = span > Int(layout.pegRadius * 1.15)
            let small = span <= Int(layout.pegRadius * 2.6)
            let ropeShaped = span * 10 >= narrow * 16
            if rope.area >= minArea && longEnough && (!small || ropeShaped) && !topCorner && !cut {
                ropes.append(rope)
            } else {
                // Leave a negative mark so these pixels are not flooded again and do not block a corridor.
                for index in queue { labels[index] = -1 }
            }
        }
    }

    // Skeletonization and arrow profiling dominate analysis time. Rope components are
    // independent, so analyze them concurrently while sharing the immutable bitmap and labels.
    let resultLock = NSLock()
    var indexedYarns: [(offset: Int, yarn: YarnReading)] = []
    indexedYarns.reserveCapacity(ropes.count)
    DispatchQueue.concurrentPerform(iterations: ropes.count) { offset in
        let rope = ropes[offset]
        let yarn = describeYarn(
            bitmap: bitmap,
            labels: labels,
            rope: rope,
            displayID: rope.id,
            field: field
        )
        resultLock.lock()
        indexedYarns.append((offset, yarn))
        resultLock.unlock()
    }
    var yarns = indexedYarns.sorted { $0.offset < $1.offset }.map(\.yarn)
    // Every rope on a board has the same thickness. Much thicker pieces are game controls, not yarn.
    let widths = yarns.filter(\.resolved).map(\.thickness).sorted()
    if !widths.isEmpty {
        let typical = widths[widths.count / 2]
        var controls: Set<Int> = []
        for i in yarns.indices where yarns[i].resolved && yarns[i].thickness > typical * 1.7 {
            yarns[i].resolved = false
            yarns[i].free = false
            controls.insert(yarns[i].id)
        }
        // A control such as the scroll bar is not yarn, so it blocks nothing.
        if !controls.isEmpty {
            for i in yarns.indices where yarns[i].resolved {
                yarns[i].blockingYarnIDs.removeAll { controls.contains($0) }
                yarns[i].free = yarns[i].blockingYarnIDs.isEmpty
            }
        }
    }
    return yarns
}

private func sameRope(_ a: RGB, _ b: RGB) -> Bool {
    if a.saturation < 0.22 && b.saturation < 0.22 {
        return a.distance(to: b) < 64
    }
    if a.saturation < 0.22 || b.saturation < 0.22 { return false }
    return hueDistance(a.hue, b.hue) < 22
}

private struct GridPoint: Hashable {
    var x: Int
    var y: Int
}

private func describeYarn(
    bitmap: Bitmap,
    labels: [Int32],
    rope: Rope,
    displayID: Int,
    field: CGRect
) -> YarnReading {
    let mean = rope.mean
    let hue = rope.dominantHue
    let empty = YarnReading(
        id: displayID,
        hue: hue,
        alternateHue: rope.alternateHue,
        saturation: mean.saturation,
        value: mean.value,
        average: mean,
        roundEnd: .zero,
        arrowTip: .zero,
        direction: CGVector(dx: 1, dy: 0),
        clickPoint: CGPoint(x: CGFloat(rope.minX + rope.maxX) / 2, y: CGFloat(rope.minY + rope.maxY) / 2),
        free: false,
        resolved: false,
        blockingYarnIDs: [],
        thickness: 0
    )

    let pad = 2
    let originX = max(0, rope.minX - pad)
    let originY = max(0, rope.minY - pad)
    let width = min(bitmap.width, rope.maxX + pad + 1) - originX
    let height = min(bitmap.height, rope.maxY + pad + 1) - originY
    guard width > 4, height > 4 else { return empty }

    var mask = [UInt8](repeating: 0, count: width * height)
    for y in rope.minY...rope.maxY {
        for x in rope.minX...rope.maxX {
            if labels[y * bitmap.width + x] == Int32(rope.id) {
                mask[(y - originY) * width + (x - originX)] = 1
            }
        }
    }
    close(&mask, width: width, height: height)
    let distances = chamfer(mask, width: width, height: height)
    let body = mask
    thin(&mask, width: width, height: height)

    var skeleton: [GridPoint] = []
    skeleton.reserveCapacity(rope.area / 4)
    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) where mask[y * width + x] == 1 {
            skeleton.append(GridPoint(x: x, y: y))
        }
    }
    guard skeleton.count >= 10 else { return empty }
    guard let path = longestSkeletonPath(mask, width: width, from: skeleton[0]), path.count >= 8 else {
        return empty
    }

    let skeletonDistances = skeleton.map { distances[$0.y * width + $0.x] }.sorted()
    let median = skeletonDistances[skeletonDistances.count / 2]
    let radius = max(2, CGFloat(median) / 3)
    guard path.count >= max(8, Int(radius * 1.6)) else { return empty }

    let thickness = ropeWidth(body, width: width, height: height, path: path, radius: radius)
    let startProfile = profileEnd(body, width: width, height: height, path: path, fromStart: true, radius: radius, rope: thickness)
    let finishProfile = profileEnd(body, width: width, height: height, path: path, fromStart: false, radius: radius, rope: thickness)
    func flat(_ point: GridPoint) -> EndProfile {
        EndProfile(flare: 0, tip: CGPoint(x: point.x, y: point.y), direction: CGVector(dx: 1, dy: 0))
    }
    let startEnd = startProfile ?? flat(path[0])
    let finishEnd = finishProfile ?? flat(path[path.count - 1])
    guard startProfile != nil || finishProfile != nil else { return empty }
    // A pale arrowhead is only a little wider than its rope. Accept that when one end is
    // plainly wider than the other. Close calls still need the full flare.
    let decisive = abs(startEnd.flare - finishEnd.flare) >= 0.30
    let flareNeeded = decisive ? min(arrowFlare, 1.15) : arrowFlare
    let arrow: EndProfile
    let roundPoint: CGPoint
    if startEnd.flare >= flareNeeded && startEnd.flare >= finishEnd.flare + flareMargin {
        arrow = startEnd
        roundPoint = finishEnd.tip
    } else if finishEnd.flare >= flareNeeded && finishEnd.flare >= startEnd.flare + flareMargin {
        arrow = finishEnd
        roundPoint = startEnd.tip
    } else {
        return empty
    }
    let direction = arrow.direction

    func global(_ point: GridPoint) -> CGPoint {
        CGPoint(x: CGFloat(point.x + originX), y: CGFloat(point.y + originY))
    }
    let tip = CGPoint(x: arrow.tip.x + CGFloat(originX), y: arrow.tip.y + CGFloat(originY))
    let round = CGPoint(x: roundPoint.x + CGFloat(originX), y: roundPoint.y + CGFloat(originY))
    let click = global(path[path.count / 2])
    let blockers = corridorBlockers(
        labels: labels,
        width: bitmap.width,
        height: bitmap.height,
        ropeID: Int32(rope.id),
        tip: tip,
        direction: direction,
        radius: radius,
        field: field
    )

    return YarnReading(
        id: displayID,
        hue: hue,
        alternateHue: rope.alternateHue,
        saturation: mean.saturation,
        value: mean.value,
        average: mean,
        roundEnd: round,
        arrowTip: tip,
        direction: direction,
        clickPoint: click,
        free: blockers.isEmpty,
        resolved: true,
        blockingYarnIDs: blockers,
        thickness: thickness
    )
}

/// An arrowhead is wider than the rope it ends. A round end is never wider than the rope.
private let arrowFlare: CGFloat = 1.3
private let flareMargin: CGFloat = 0.15

private struct EndProfile {
    /// Widest cross-section near the end, over the rope's own width.
    var flare: CGFloat
    /// Last rope pixel along the end's axis, in local coordinates.
    var tip: CGPoint
    var direction: CGVector
}

/// Wider than this over the rope is a fold or a bend, not an arrowhead.
private let flareCeiling: CGFloat = 2.0

private func bodyContains(_ body: [UInt8], _ width: Int, _ height: Int, _ x: CGFloat, _ y: CGFloat) -> Bool {
    let ix = Int(x.rounded())
    let iy = Int(y.rounded())
    guard ix >= 0, iy >= 0, ix < width, iy < height else { return false }
    return body[iy * width + ix] == 1
}

private func bodyCrossWidth(
    _ body: [UInt8], _ width: Int, _ height: Int,
    x: CGFloat, y: CGFloat, axis: CGVector, reach: CGFloat
) -> CGFloat {
    let px = -axis.dy
    let py = axis.dx
    var w: CGFloat = 1
    for sign in [CGFloat(-1), 1] {
        var t: CGFloat = 1
        while t <= reach, bodyContains(body, width, height, x + px * t * sign, y + py * t * sign) {
            w += 1
            t += 1
        }
    }
    return w
}

/// Typical rope width, measured across the rope at points along its centerline.
private func ropeWidth(_ body: [UInt8], width: Int, height: Int, path: [GridPoint], radius: CGFloat) -> CGFloat {
    let span = max(2, Int(radius))
    var samples: [CGFloat] = []
    var i = span
    while i < path.count - span {
        let a = path[i - span]
        let b = path[i + span]
        if let axis = snappedAxis(dx: CGFloat(b.x - a.x), dy: CGFloat(b.y - a.y)) {
            let p = path[i]
            samples.append(bodyCrossWidth(body, width, height, x: CGFloat(p.x), y: CGFloat(p.y), axis: axis, reach: radius * 4))
        }
        i += 2
    }
    guard !samples.isEmpty else { return max(2, radius * 2) }
    let sorted = samples.sorted()
    // A short yarn is mostly arrowhead, so its median width includes the head. Use the narrow
    // part there. Longer ropes keep the median, so a thin spot does not shrink the reference.
    if path.count < Int(radius * 6) {
        return sorted[sorted.count / 5]
    }
    return sorted[sorted.count / 2]
}

/// The centerline can end in one barb of the arrowhead, so a few distances back are tried and the axis
/// with the longest straight run through the end wins.
private func profileEnd(
    _ body: [UInt8],
    width: Int,
    height: Int,
    path: [GridPoint],
    fromStart: Bool,
    radius: CGFloat,
    rope: CGFloat
) -> EndProfile? {
    let base = max(4, Int(radius * 3.5))
    var best: (run: Int, profile: EndProfile)?
    for back in [base / 2, base, base * 2] {
        let clamped = min(path.count - 1, max(2, back))
        guard let found = walkEnd(
            body, width: width, height: height, path: path,
            fromStart: fromStart, back: clamped, radius: radius, rope: rope
        ) else { continue }
        if best == nil || found.run > best!.run {
            best = found
        }
    }
    return best?.profile
}

/// Walks straight out through one end of the rope and measures its width at each step.
private func walkEnd(
    _ body: [UInt8],
    width: Int,
    height: Int,
    path: [GridPoint],
    fromStart: Bool,
    back: Int,
    radius: CGFloat,
    rope: CGFloat
) -> (run: Int, profile: EndProfile)? {
    let end = fromStart ? path[0] : path[path.count - 1]
    let inner = fromStart ? path[back] : path[path.count - 1 - back]
    guard let axis = snappedAxis(dx: CGFloat(end.x - inner.x), dy: CGFloat(end.y - inner.y)) else { return nil }

    func inside(_ x: CGFloat, _ y: CGFloat) -> Bool {
        bodyContains(body, width, height, x, y)
    }
    func crossWidth(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        bodyCrossWidth(body, width, height, x: x, y: y, axis: axis, reach: radius * 4)
    }

    // Walk on the line through the end point, so a stepped or hooked end still stays on its last straight piece.
    var startX = CGFloat(end.x)
    var startY = CGFloat(end.y)
    var t: CGFloat = 1
    while t <= max(CGFloat(back), radius * 4), inside(startX - axis.dx, startY - axis.dy) {
        startX -= axis.dx
        startY -= axis.dy
        t += 1
    }
    var widths: [CGFloat] = []
    var tip = CGPoint(x: startX, y: startY)
    var s: CGFloat = 0
    let limit = max(CGFloat(back), radius * 4) + radius * 6
    while s <= limit {
        let x = startX + axis.dx * s
        let y = startY + axis.dy * s
        guard inside(x, y) else { break }
        widths.append(crossWidth(x, y))
        tip = CGPoint(x: x.rounded(), y: y.rounded())
        s += 1
    }
    guard widths.count >= 3 else {
        return nil
    }
    // The arrowhead sits right before the tip; a bend further back must not count as a flare.
    let head = min(widths.count, max(3, Int((radius * 3.2).rounded(.up))))
    let widest = widths.suffix(head).max() ?? 0
    var flare = widest / max(rope, 2)
    if flare > flareCeiling { flare = 0 }
    return (widths.count, EndProfile(flare: flare, tip: tip, direction: axis))
}

/// The board is a grid, so ends point straight up, down, left, or right.
private func snappedAxis(dx: CGFloat, dy: CGFloat) -> CGVector? {
    let length = (dx * dx + dy * dy).squareRoot()
    guard length > 0.5 else { return nil }
    if abs(dx) >= abs(dy) {
        return CGVector(dx: dx > 0 ? 1 : -1, dy: 0)
    }
    return CGVector(dx: 0, dy: dy > 0 ? 1 : -1)
}

private func longestSkeletonPath(_ mask: [UInt8], width: Int, from start: GridPoint) -> [GridPoint]? {
    let first = farthestSkeletonPoint(mask, width: width, from: start)
    let second = farthestSkeletonPoint(mask, width: width, from: first.point)
    var path = [second.point]
    var cursor = second.point
    while cursor != first.point, let previous = second.parent[cursor] {
        path.append(previous)
        cursor = previous
    }
    guard path.count >= 2, cursor == first.point else { return nil }
    return path
}

private func farthestSkeletonPoint(
    _ mask: [UInt8],
    width: Int,
    from start: GridPoint
) -> (point: GridPoint, parent: [GridPoint: GridPoint]) {
    let height = mask.count / width
    var queue = [start]
    var head = 0
    var parent: [GridPoint: GridPoint] = [:]
    var seen: Set<GridPoint> = [start]
    var farthest = start
    while head < queue.count {
        let point = queue[head]
        head += 1
        farthest = point
        for j in (point.y - 1)...(point.y + 1) {
            guard j >= 0, j < height else { continue }
            for i in (point.x - 1)...(point.x + 1) {
                if i == point.x && j == point.y { continue }
                guard i >= 0, i < width else { continue }
                guard mask[j * width + i] == 1 else { continue }
                let next = GridPoint(x: i, y: j)
                if seen.contains(next) { continue }
                seen.insert(next)
                parent[next] = point
                queue.append(next)
            }
        }
    }
    return (farthest, parent)
}

private func corridorBlockers(
    labels: [Int32],
    width: Int,
    height: Int,
    ropeID: Int32,
    tip: CGPoint,
    direction: CGVector,
    radius: CGFloat,
    field: CGRect
) -> [Int] {
    let spread = radius * 0.7
    let px = -direction.dy
    let py = direction.dx
    var t: CGFloat = 2
    let limit = max(field.width, field.height) + radius
    var blockers: [Int] = []
    var seen: Set<Int32> = []
    while t < limit {
        let x = tip.x + direction.dx * t
        let y = tip.y + direction.dy * t
        let point = CGPoint(x: x, y: y)
        if !field.contains(point) { return blockers }
        for s in [-spread, 0, spread] {
            let sx = Int((x + px * s).rounded())
            let sy = Int((y + py * s).rounded())
            guard sx >= 0, sy >= 0, sx < width, sy < height else { return blockers }
            let label = labels[sy * width + sx]
            if label > 0 && label != ropeID && seen.insert(label).inserted {
                blockers.append(Int(label))
            }
        }
        t += 1
    }
    return blockers
}

/// Fills one-pixel holes and notches. Pale ropes have texture pixels that fall below the saturation cut.
private func close(_ mask: inout [UInt8], width: Int, height: Int) {
    var grown = mask
    for y in 0..<height {
        for x in 0..<width where mask[y * width + x] == 0 {
            search: for j in max(0, y - 1)...min(height - 1, y + 1) {
                for i in max(0, x - 1)...min(width - 1, x + 1) where mask[j * width + i] == 1 {
                    grown[y * width + x] = 1
                    break search
                }
            }
        }
    }
    var shrunk = grown
    for y in 0..<height {
        for x in 0..<width where grown[y * width + x] == 1 {
            var keep = true
            search: for j in (y - 1)...(y + 1) {
                for i in (x - 1)...(x + 1) {
                    if j < 0 || i < 0 || j >= height || i >= width || grown[j * width + i] == 0 {
                        keep = false
                        break search
                    }
                }
            }
            if !keep { shrunk[y * width + x] = mask[y * width + x] }
        }
    }
    mask = shrunk
}

private func chamfer(_ mask: [UInt8], width: Int, height: Int) -> [Int] {
    let inf = 10_000_000
    var dt = [Int](repeating: 0, count: width * height)
    for i in 0..<dt.count {
        dt[i] = mask[i] == 0 ? 0 : inf
    }
    for y in 0..<height {
        for x in 0..<width {
            let i = y * width + x
            guard mask[i] == 1 else { continue }
            if x > 0 { dt[i] = min(dt[i], dt[i - 1] + 3) }
            if y > 0 { dt[i] = min(dt[i], dt[i - width] + 3) }
            if x > 0, y > 0 { dt[i] = min(dt[i], dt[i - width - 1] + 4) }
            if x + 1 < width, y > 0 { dt[i] = min(dt[i], dt[i - width + 1] + 4) }
        }
    }
    for y in stride(from: height - 1, through: 0, by: -1) {
        for x in stride(from: width - 1, through: 0, by: -1) {
            let i = y * width + x
            guard mask[i] == 1 else { continue }
            if x + 1 < width { dt[i] = min(dt[i], dt[i + 1] + 3) }
            if y + 1 < height { dt[i] = min(dt[i], dt[i + width] + 3) }
            if x + 1 < width, y + 1 < height { dt[i] = min(dt[i], dt[i + width + 1] + 4) }
            if x > 0, y + 1 < height { dt[i] = min(dt[i], dt[i + width - 1] + 4) }
        }
    }
    return dt
}

private func thin(_ mask: inout [UInt8], width: Int, height: Int) {
    func neighbors(_ x: Int, _ y: Int) -> [Int] {
        let row = y * width
        return [
            Int(mask[(y - 1) * width + x]),
            Int(mask[(y - 1) * width + x + 1]),
            Int(mask[row + x + 1]),
            Int(mask[(y + 1) * width + x + 1]),
            Int(mask[(y + 1) * width + x]),
            Int(mask[(y + 1) * width + x - 1]),
            Int(mask[row + x - 1]),
            Int(mask[(y - 1) * width + x - 1]),
        ]
    }
    func transitions(_ n: [Int]) -> Int {
        var count = 0
        for i in 0..<8 where n[i] == 0 && n[(i + 1) % 8] == 1 {
            count += 1
        }
        return count
    }

    var changed = true
    var guardrail = 0
    while changed && guardrail < 80 {
        changed = false
        guardrail += 1
        for phase in 0...1 {
            var clear: [Int] = []
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    if mask[index] == 0 { continue }
                    let n = neighbors(x, y)
                    let b = n.reduce(0, +)
                    if b < 2 || b > 6 || transitions(n) != 1 { continue }
                    if phase == 0 {
                        if n[0] * n[2] * n[4] != 0 { continue }
                        if n[2] * n[4] * n[6] != 0 { continue }
                    } else {
                        if n[0] * n[2] * n[6] != 0 { continue }
                        if n[0] * n[4] * n[6] != 0 { continue }
                    }
                    clear.append(index)
                }
            }
            if !clear.isEmpty {
                changed = true
                for index in clear { mask[index] = 0 }
            }
        }
    }
}

private func pickTargets(yarns: [YarnReading], couches: [CouchReading], pegs: [PegReading]) -> [YarnTarget] {
    let open = couches.filter { !$0.locked && $0.openSlots > 0 }
    guard let active = activeCouch(in: open) else { return [] }
    let free = yarns.filter(\.resolved).filter(\.free).sorted {
        if $0.clickPoint.y != $1.clickPoint.y { return $0.clickPoint.y < $1.clickPoint.y }
        return $0.clickPoint.x < $1.clickPoint.x
    }

    // Finish one couch before touching another. Prefer a direct move whenever one is free.
    let direct = free
        .filter { matches($0, couch: active) }
        .prefix(active.openSlots)
        .map { YarnTarget(yarn: $0, reason: .couch, couchIndex: active.index) }
    if !direct.isEmpty {
        return Array(direct)
    }

    // Backtrack from every yarn for the active couch through its forward blockers.
    let byID = Dictionary(uniqueKeysWithValues: yarns.map { ($0.id, $0) })
    var queue: [(id: Int, depth: Int)] = yarns
        .filter { matches($0, couch: active) }
        .flatMap { yarn in yarn.blockingYarnIDs.map { ($0, 1) } }
    var head = 0
    var visited: Set<Int> = []
    var blockers: [(depth: Int, yarn: YarnReading)] = []
    while head < queue.count {
        let next = queue[head]
        head += 1
        guard visited.insert(next.id).inserted, let yarn = byID[next.id] else { continue }
        if yarn.resolved && yarn.free {
            blockers.append((next.depth, yarn))
        } else {
            queue.append(contentsOf: yarn.blockingYarnIDs.map { ($0, next.depth + 1) })
        }
    }
    blockers.sort {
        if $0.depth != $1.depth { return $0.depth < $1.depth }
        if $0.yarn.clickPoint.y != $1.yarn.clickPoint.y {
            return $0.yarn.clickPoint.y < $1.yarn.clickPoint.y
        }
        return $0.yarn.clickPoint.x < $1.yarn.clickPoint.x
    }

    // A blocker of another open couch's color goes to that couch and costs no buffer peg.
    let others = open.filter { $0.index != active.index }
    var room = Dictionary(uniqueKeysWithValues: others.map { ($0.index, $0.openSlots) })
    func toOtherCouch(_ candidates: [YarnReading]) -> [YarnTarget] {
        var targets: [YarnTarget] = []
        for yarn in candidates {
            guard let couch = matchingCouch(for: yarn, among: others), (room[couch.index] ?? 0) > 0 else { continue }
            room[couch.index, default: 0] -= 1
            targets.append(YarnTarget(yarn: yarn, reason: .couch, couchIndex: couch.index))
        }
        return targets
    }
    let freeingForCouch = toOtherCouch(blockers.map(\.yarn))
    if !freeingForCouch.isEmpty {
        return freeingForCouch
    }

    // Any free yarn that fits another open couch is still better than parking a wrong color.
    let otherCouch = toOtherCouch(free)
    if !otherCouch.isEmpty {
        return otherCouch
    }

    // A full five-peg buffer loses the level. Keep the final peg empty at all times.
    let occupied = pegs.filter(\.occupied).count
    let safeBufferRoom = max(0, pegs.count - occupied - 1)
    return blockers
        .filter { matchingCouch(for: $0.yarn, among: open) == nil }
        .prefix(safeBufferRoom)
        .map { YarnTarget(yarn: $0.yarn, reason: .buffer, couchIndex: active.index) }
}

/// Continue the couch already nearest completion. The leftmost couch breaks a tie.
private func activeCouch(in couches: [CouchReading]) -> CouchReading? {
    couches.sorted {
        if $0.filledSlots != $1.filledSlots { return $0.filledSlots > $1.filledSlots }
        return $0.index < $1.index
    }.first
}

/// Pale shades share a hue with deep ones (lavender and royal blue, mint and green), so the
/// saturation must agree too. Same-color pairs measured within 0.05; look-alikes 0.24 or more apart.
private let saturationMatch: Float = 0.15

private func matches(_ yarn: YarnReading, couch: CouchReading) -> Bool {
    // White has no stable hue, so two near-gray colors match by their actual color.
    if yarn.saturation < 0.12 || couch.color.saturation < 0.12 {
        return yarn.saturation < 0.12 && couch.color.saturation < 0.12
            && yarn.average.distance(to: couch.color) < 48
    }
    guard abs(yarn.saturation - couch.color.saturation) <= saturationMatch else { return false }
    return [yarn.hue, yarn.alternateHue].compactMap { $0 }.contains {
        hueDistance(couch.hue, $0) <= 16
    }
}

private func matchingCouch(for yarn: YarnReading, among couches: [CouchReading]) -> CouchReading? {
    let yarnHues = [yarn.hue, yarn.alternateHue].compactMap { $0 }
    return couches
        .filter { matches(yarn, couch: $0) }
        .min { lhs, rhs in
            let left = yarnHues.map { hueDistance(lhs.hue, $0) }.min() ?? 999
            let right = yarnHues.map { hueDistance(rhs.hue, $0) }.min() ?? 999
            return left < right
        }
}

func describe(layout: Layout) -> String {
    var lines: [String] = []
    lines.append("Game screen confirmed.")
    lines.append(String(format: "Tray %.0f,%.0f  %.0fx%.0f", layout.tray.minX, layout.tray.minY, layout.tray.width, layout.tray.height))
    lines.append(String(format: "Field %.0f,%.0f  %.0fx%.0f", layout.field.minX, layout.field.minY, layout.field.width, layout.field.height))
    for couch in layout.couches {
        if couch.locked {
            lines.append("Couch \(couch.index): locked")
        } else {
            lines.append("Couch \(couch.index): \(couch.color.hex)  \(couch.filledSlots)/3")
        }
    }
    let occupied = layout.pegs.filter(\.occupied).count
    lines.append("Buffer pegs: \(occupied)/\(layout.pegs.count) occupied")
    lines.append("Press 1 to capture, analyze, and click the next yarn.")
    return lines.joined(separator: "\n")
}

func describe(board: BoardReading) -> String {
    var lines: [String] = []
    lines.append("Analysis")
    for couch in board.couches {
        if couch.locked {
            lines.append("Couch \(couch.index): locked")
        } else {
            lines.append("Couch \(couch.index): \(couch.color.hex)  \(couch.filledSlots)/3  room \(couch.openSlots)")
        }
    }
    if let active = activeCouch(in: board.couches.filter { !$0.locked && $0.openSlots > 0 }) {
        lines.append("Active couch: \(active.index) — finish it before another couch")
    }
    let occupied = board.pegs.filter(\.occupied).count
    lines.append("Buffer pegs: \(occupied)/\(board.pegs.count) occupied")
    if ProcessInfo.processInfo.environment["YARNJAM_DEBUG"] != nil {
        for yarn in board.yarns {
            lines.append(
                String(
                    format: "  yarn %d %@ hue %.0f%@ %@ tip %.0f,%.0f dir %.0f,%.0f blockers %@",
                    yarn.id,
                    yarn.average.hex,
                    yarn.hue,
                    yarn.alternateHue.map { String(format: "/%.0f", $0) } ?? "",
                    !yarn.resolved ? "unresolved" : (yarn.free ? "free" : "blocked"),
                    yarn.arrowTip.x,
                    yarn.arrowTip.y,
                    yarn.direction.dx,
                    yarn.direction.dy,
                    yarn.blockingYarnIDs.map(String.init).joined(separator: ",")
                )
            )
        }
        for couch in board.couches where !couch.locked {
            lines.append(String(format: "  couch %d hue %.0f", couch.index, couch.hue))
        }
    }
    let resolved = board.yarns.filter(\.resolved)
    let free = resolved.filter(\.free).count
    let blocked = resolved.filter { !$0.free }.count
    let unresolved = board.yarns.count - resolved.count
    lines.append("Yarns: \(resolved.count) read, \(free) free, \(blocked) blocked, \(unresolved) unresolved")
    if board.targets.isEmpty {
        lines.append("No safe target for the active couch. The bot will not fill the last buffer peg.")
    } else {
        lines.append("Targets (\(board.targets.count)). The first one is clicked.")
        for (index, target) in board.targets.enumerated() {
            let yarn = target.yarn
            lines.append(
                String(
                    format: "  %d. %@  %@  at %.0f,%.0f",
                    index + 1,
                    yarn.average.hex,
                    target.label,
                    yarn.clickPoint.x,
                    yarn.clickPoint.y
                )
            )
        }
    }
    lines.append("Wrote debug/last-analysis.png")
    return lines.joined(separator: "\n")
}
