import AppKit

let width: CGFloat = 640
let height: CGFloat = 420
let outputPath = "/Volumes/SSD/Projects/Aether/App/Scripts/Resources/dmg_background.png"

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context.")
}

let rect = CGRect(x: 0, y: 0, width: width, height: height)

let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.14, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.12, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

context.setFillColor(NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.07, alpha: 0.22).cgColor)
context.fill(rect)

func drawGlow(center: CGPoint, radius: CGFloat, color: NSColor) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color.withAlphaComponent(0.52).cgColor,
            color.withAlphaComponent(0.18).cgColor,
            color.withAlphaComponent(0.0).cgColor
        ] as CFArray,
        locations: [0, 0.42, 1]
    )!
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
}

drawGlow(center: CGPoint(x: 120, y: 160), radius: 210, color: NSColor(calibratedRed: 0.23, green: 0.96, blue: 0.98, alpha: 1))
drawGlow(center: CGPoint(x: 520, y: 160), radius: 220, color: NSColor(calibratedRed: 0.78, green: 0.55, blue: 1.00, alpha: 1))

func drawRibbon(_ points: [CGPoint], color: NSColor, width: CGFloat, alpha: CGFloat, glow: CGFloat) {
    guard points.count >= 2 else { return }

    let path = NSBezierPath()
    path.move(to: points[0])
    if points.count == 4 {
        path.curve(
            to: points[3],
            controlPoint1: points[1],
            controlPoint2: points[2]
        )
    } else {
        for point in points.dropFirst() {
            path.line(to: point)
        }
    }

    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: glow,
        color: color.withAlphaComponent(alpha * 0.65).cgColor
    )
    context.addPath(path.cgPath)
    context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.strokePath()
    context.restoreGState()
}

drawRibbon(
    [
        CGPoint(x: -40, y: 85),
        CGPoint(x: 95, y: 255),
        CGPoint(x: 215, y: 205),
        CGPoint(x: 335, y: 110)
    ],
    color: NSColor(calibratedRed: 0.32, green: 0.98, blue: 0.98, alpha: 1),
    width: 24,
    alpha: 0.16,
    glow: 28
)
drawRibbon(
    [
        CGPoint(x: 530, y: 48),
        CGPoint(x: 625, y: 125),
        CGPoint(x: 690, y: 255),
        CGPoint(x: 560, y: 315)
    ],
    color: NSColor(calibratedRed: 0.72, green: 0.54, blue: 1.00, alpha: 1),
    width: 22,
    alpha: 0.14,
    glow: 26
)
drawRibbon(
    [
        CGPoint(x: 35, y: 35),
        CGPoint(x: 110, y: 115),
        CGPoint(x: 190, y: 102),
        CGPoint(x: 250, y: 52)
    ],
    color: NSColor(calibratedRed: 0.28, green: 0.96, blue: 1.00, alpha: 1),
    width: 10,
    alpha: 0.32,
    glow: 18
)
drawRibbon(
    [
        CGPoint(x: 388, y: 48),
        CGPoint(x: 492, y: 108),
        CGPoint(x: 562, y: 70),
        CGPoint(x: 650, y: 118)
    ],
    color: NSColor(calibratedRed: 0.82, green: 0.62, blue: 1.00, alpha: 1),
    width: 12,
    alpha: 0.28,
    glow: 18
)

context.setLineWidth(5)
let arrowPath = NSBezierPath()
arrowPath.move(to: CGPoint(x: 245, y: 155))
arrowPath.line(to: CGPoint(x: 382, y: 155))
arrowPath.line(to: CGPoint(x: 382, y: 190))
arrowPath.line(to: CGPoint(x: 455, y: 140))
arrowPath.line(to: CGPoint(x: 382, y: 90))
arrowPath.line(to: CGPoint(x: 382, y: 125))
arrowPath.line(to: CGPoint(x: 245, y: 125))
arrowPath.close()

context.saveGState()
context.addPath(arrowPath.cgPath)
context.clip()
let arrowGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.31, green: 0.98, blue: 0.98, alpha: 0.72).cgColor,
        NSColor(calibratedRed: 0.56, green: 0.86, blue: 1.0, alpha: 0.84).cgColor,
        NSColor(calibratedRed: 0.77, green: 0.58, blue: 1.0, alpha: 0.82).cgColor
    ] as CFArray,
    locations: [0, 0.5, 1]
)!
context.drawLinearGradient(arrowGradient, start: CGPoint(x: 245, y: 140), end: CGPoint(x: 455, y: 140), options: [])
context.restoreGState()

context.addPath(arrowPath.cgPath)
context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
context.strokePath()

func drawPedestal(centerX: CGFloat, baseColor: NSColor) {
    let pedestalRect = CGRect(x: centerX - 85, y: 18, width: 170, height: 100)
    let path = NSBezierPath(roundedRect: pedestalRect, xRadius: 28, yRadius: 28)

    context.saveGState()
    context.addPath(path.cgPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            baseColor.withAlphaComponent(0.62).cgColor,
            baseColor.withAlphaComponent(0.24).cgColor,
            NSColor.black.withAlphaComponent(0.10).cgColor
        ] as CFArray,
        locations: [0, 0.58, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: pedestalRect.midX, y: pedestalRect.maxY),
        end: CGPoint(x: pedestalRect.midX, y: pedestalRect.minY),
        options: []
    )
    context.restoreGState()

    context.addPath(path.cgPath)
    context.setShadow(offset: .zero, blur: 18, color: baseColor.withAlphaComponent(0.25).cgColor)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    context.strokePath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
}

drawPedestal(centerX: 150, baseColor: NSColor(calibratedRed: 0.42, green: 0.98, blue: 1.0, alpha: 1))
drawPedestal(centerX: 450, baseColor: NSColor(calibratedRed: 0.82, green: 0.62, blue: 1.0, alpha: 1))

func drawStarField() {
    for index in 0..<90 {
        let x = CGFloat((index * 73) % 620) + 10
        let y = CGFloat((index * 41) % 360) + 40
        let size = CGFloat((index % 3) + 1)
        let alpha = 0.08 + CGFloat(index % 5) * 0.03
        let starRect = CGRect(x: x, y: y, width: size, height: size)
        context.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        context.fillEllipse(in: starRect)
    }
}

drawStarField()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Unable to export PNG.")
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
