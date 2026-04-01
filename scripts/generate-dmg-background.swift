#!/usr/bin/env swift

import AppKit

let arguments = CommandLine.arguments.dropFirst()
guard let outputPath = arguments.first else {
  fputs("Usage: generate-dmg-background.swift OUTPUT_PATH [SCALE]\n", stderr)
  exit(1)
}

let scale = max(1, Int(arguments.dropFirst().first ?? "1") ?? 1)
let scaleFactor = CGFloat(scale)
func scaled(_ value: CGFloat) -> CGFloat { value * scaleFactor }

let canvasSize = NSSize(width: scaled(720), height: scaled(460))
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)

func color(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
  NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func drawGlow(center: CGPoint, radius: CGFloat, color: NSColor) {
  let rect = CGRect(
    x: center.x - radius,
    y: center.y - radius,
    width: radius * 2,
    height: radius * 2
  )
  let path = NSBezierPath(ovalIn: rect)
  let gradient = NSGradient(
    starting: color.withAlphaComponent(0.85),
    ending: color.withAlphaComponent(0.0)
  )
  gradient?.draw(in: path, relativeCenterPosition: .zero)
}

guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(canvasSize.width),
  pixelsHigh: Int(canvasSize.height),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fputs("Error: unable to allocate bitmap buffer\n", stderr)
  exit(1)
}

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fputs("Error: unable to create graphics context\n", stderr)
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

guard let context = NSGraphicsContext.current?.cgContext else {
  fputs("Error: unable to acquire graphics context\n", stderr)
  exit(1)
}

context.setShouldAntialias(true)
context.interpolationQuality = .high

let fullRect = NSRect(origin: .zero, size: canvasSize)
let baseGradient = NSGradient(colorsAndLocations:
  (color(red: 24, green: 35, blue: 108), 0.0),
  (color(red: 27, green: 123, blue: 244), 0.47),
  (color(red: 195, green: 247, blue: 252), 1.0)
)
baseGradient?.draw(in: fullRect, angle: 34)

let lowerShadePath = NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasSize.width, height: scaled(170)))
let lowerShade = NSGradient(colorsAndLocations:
  (color(red: 10, green: 20, blue: 76, alpha: 0.88), 0.0),
  (color(red: 10, green: 20, blue: 76, alpha: 0.0), 1.0)
)
lowerShade?.draw(in: lowerShadePath, angle: 90)

drawGlow(center: CGPoint(x: scaled(178), y: scaled(210)), radius: scaled(150), color: color(red: 102, green: 225, blue: 255))
drawGlow(center: CGPoint(x: scaled(544), y: scaled(210)), radius: scaled(155), color: color(red: 212, green: 246, blue: 255))
drawGlow(center: CGPoint(x: scaled(360), y: scaled(224)), radius: scaled(120), color: color(red: 255, green: 165, blue: 82))

let panelRect = NSRect(x: scaled(36), y: scaled(300), width: scaled(434), height: scaled(126))
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: scaled(26), yRadius: scaled(26))
color(red: 255, green: 255, blue: 255, alpha: 0.14).setFill()
panelPath.fill()
color(red: 255, green: 255, blue: 255, alpha: 0.22).setStroke()
panelPath.lineWidth = scaled(1)
panelPath.stroke()

let badgeRect = NSRect(x: scaled(54), y: scaled(392), width: scaled(110), height: scaled(24))
let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: scaled(12), yRadius: scaled(12))
color(red: 255, green: 255, blue: 255, alpha: 0.18).setFill()
badgePath.fill()

let badgeText = NSAttributedString(
  string: "MACOS INSTALLER",
  attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: scaled(11), weight: .semibold),
    .foregroundColor: color(red: 242, green: 248, blue: 255, alpha: 0.92),
    .kern: scaled(1.1)
  ]
)
badgeText.draw(at: CGPoint(x: scaled(66), y: scaled(399)))

let titleText = NSAttributedString(
  string: "Install CoPaRe",
  attributes: [
    .font: NSFont.systemFont(ofSize: scaled(34), weight: .bold),
    .foregroundColor: color(red: 255, green: 255, blue: 255, alpha: 0.98)
  ]
)
titleText.draw(at: CGPoint(x: scaled(52), y: scaled(354)))

let subtitle = "Drag the app into Applications.\nYour current copy will be replaced cleanly."
let subtitleStyle = NSMutableParagraphStyle()
subtitleStyle.lineSpacing = scaled(3)

let subtitleText = NSAttributedString(
  string: subtitle,
  attributes: [
    .font: NSFont.systemFont(ofSize: scaled(15), weight: .medium),
    .foregroundColor: color(red: 232, green: 243, blue: 252, alpha: 0.94),
    .paragraphStyle: subtitleStyle
  ]
)
subtitleText.draw(in: NSRect(x: scaled(54), y: scaled(306), width: scaled(360), height: scaled(44)))

let arrowShadow = NSBezierPath()
arrowShadow.move(to: CGPoint(x: scaled(278), y: scaled(214)))
arrowShadow.line(to: CGPoint(x: scaled(436), y: scaled(214)))
arrowShadow.lineCapStyle = .round
arrowShadow.lineJoinStyle = .round
arrowShadow.lineWidth = scaled(14)
color(red: 14, green: 28, blue: 84, alpha: 0.22).setStroke()
arrowShadow.stroke()

let arrowPath = NSBezierPath()
arrowPath.move(to: CGPoint(x: scaled(278), y: scaled(220)))
arrowPath.line(to: CGPoint(x: scaled(448), y: scaled(220)))
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
arrowPath.lineWidth = scaled(10)
color(red: 255, green: 177, blue: 92, alpha: 0.95).setStroke()
arrowPath.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: CGPoint(x: scaled(448), y: scaled(220)))
arrowHead.line(to: CGPoint(x: scaled(423), y: scaled(238)))
arrowHead.move(to: CGPoint(x: scaled(448), y: scaled(220)))
arrowHead.line(to: CGPoint(x: scaled(423), y: scaled(202)))
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.lineWidth = scaled(10)
color(red: 255, green: 177, blue: 92, alpha: 0.95).setStroke()
arrowHead.stroke()

let footerText = NSAttributedString(
  string: "A clean drag-and-drop install, without extra Finder steps.",
  attributes: [
    .font: NSFont.systemFont(ofSize: scaled(13), weight: .medium),
    .foregroundColor: color(red: 230, green: 239, blue: 248, alpha: 0.84)
  ]
)
footerText.draw(at: CGPoint(x: scaled(36), y: scaled(24)))

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Error: unable to encode PNG output\n", stderr)
  exit(1)
}

try pngData.write(to: outputURL)
