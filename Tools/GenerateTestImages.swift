#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageSpec {
  let filename: String
  let width: Int
  let height: Int
  let colors: [NSColor]
}

let specifications = [
  ImageSpec(
    filename: "01_narrow_short_640x1800.jpg",
    width: 640,
    height: 1_800,
    colors: [
      NSColor(calibratedRed: 0.16, green: 0.43, blue: 0.91, alpha: 1),
      NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.73, alpha: 1),
    ]
  ),
  ImageSpec(
    filename: "02_phone_medium_1284x5000.jpg",
    width: 1_284,
    height: 5_000,
    colors: [
      NSColor(calibratedRed: 0.50, green: 0.24, blue: 0.88, alpha: 1),
      NSColor(calibratedRed: 0.95, green: 0.31, blue: 0.55, alpha: 1),
    ]
  ),
  ImageSpec(
    filename: "03_wide_medium_2400x6000.jpg",
    width: 2_400,
    height: 6_000,
    colors: [
      NSColor(calibratedRed: 0.94, green: 0.47, blue: 0.12, alpha: 1),
      NSColor(calibratedRed: 0.96, green: 0.76, blue: 0.14, alpha: 1),
    ]
  ),
  ImageSpec(
    filename: "10_ultra_long_1284x18000.jpg",
    width: 1_284,
    height: 18_000,
    colors: [
      NSColor(calibratedRed: 0.04, green: 0.55, blue: 0.36, alpha: 1),
      NSColor(calibratedRed: 0.16, green: 0.76, blue: 0.52, alpha: 1),
    ]
  ),
  ImageSpec(
    filename: "20_wide_short_1800x1500.jpg",
    width: 1_800,
    height: 1_500,
    colors: [
      NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.34, alpha: 1),
      NSColor(calibratedRed: 0.32, green: 0.44, blue: 0.65, alpha: 1),
    ]
  ),
  ImageSpec(
    filename: "Z_tall_narrow_900x12000.jpg",
    width: 900,
    height: 12_000,
    colors: [
      NSColor(calibratedRed: 0.70, green: 0.12, blue: 0.18, alpha: 1),
      NSColor(calibratedRed: 0.96, green: 0.36, blue: 0.24, alpha: 1),
    ]
  ),
]

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
  .standardizedFileURL
let projectURL =
  scriptURL
  .deletingLastPathComponent()
  .deletingLastPathComponent()
let outputURL = projectURL.appendingPathComponent(
  "TestImages",
  isDirectory: true
)

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(
  at: outputURL,
  withIntermediateDirectories: true
)

for specification in specifications {
  autoreleasepool {
    let size = CGSize(
      width: specification.width,
      height: specification.height
    )
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: specification.width,
        height: specification.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else {
      fatalError("Unable to create bitmap context")
    }
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)

    let graphicsContext = NSGraphicsContext(
      cgContext: context,
      flipped: true
    )
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    drawBackground(
      in: context,
      size: size,
      colors: specification.colors
    )
    drawHeader(specification, in: context)
    drawSections(specification, in: context)
    drawRulers(specification, in: context)
    drawFooter(specification, in: context)
    NSGraphicsContext.restoreGraphicsState()

    guard
      let cgImage = context.makeImage()
    else {
      fatalError("Unable to create \(specification.filename)")
    }

    let fileURL = outputURL.appendingPathComponent(
      specification.filename
    )
    guard
      let destination = CGImageDestinationCreateWithURL(
        fileURL as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      fatalError("Unable to open \(specification.filename)")
    }
    let properties =
      [
        kCGImageDestinationLossyCompressionQuality: 0.88
      ] as CFDictionary
    CGImageDestinationAddImage(destination, cgImage, properties)
    guard CGImageDestinationFinalize(destination) else {
      fatalError("Unable to encode \(specification.filename)")
    }
    print("Generated \(specification.filename)")
  }
}

func drawBackground(
  in context: CGContext,
  size: NSSize,
  colors: [NSColor]
) {
  let cgColors = colors.map(\.cgColor) as CFArray
  let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: cgColors,
    locations: [0, 1]
  )!
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: size.width, y: size.height),
    options: []
  )
}

func drawHeader(_ specification: ImageSpec, in context: CGContext) {
  let width = CGFloat(specification.width)
  let horizontalPadding = max(32, width * 0.055)
  let headerHeight = min(440, max(250, width * 0.34))

  context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
  context.fill(
    CGRect(x: 0, y: 0, width: width, height: headerHeight)
  )

  drawText(
    "LONG IMAGE TEST",
    at: CGPoint(x: horizontalPadding, y: horizontalPadding),
    fontSize: max(28, width * 0.045),
    weight: .bold,
    color: .white
  )
  drawText(
    specification.filename,
    at: CGPoint(
      x: horizontalPadding,
      y: horizontalPadding + max(60, width * 0.075)
    ),
    fontSize: max(20, width * 0.032),
    weight: .semibold,
    color: .white
  )
  drawText(
    "\(specification.width) x \(specification.height) px",
    at: CGPoint(
      x: horizontalPadding,
      y: horizontalPadding + max(108, width * 0.132)
    ),
    fontSize: max(18, width * 0.027),
    weight: .regular,
    color: NSColor.white.withAlphaComponent(0.84)
  )
}

func drawSections(_ specification: ImageSpec, in context: CGContext) {
  let width = CGFloat(specification.width)
  let height = CGFloat(specification.height)
  let sectionHeight = max(520, min(1_400, width * 0.82))
  let firstSectionY = min(500, max(300, width * 0.40))
  let sectionCount = max(
    1,
    Int(ceil((height - firstSectionY) / sectionHeight))
  )
  let sidePadding = max(28, width * 0.045)

  for index in 0..<sectionCount {
    let y = firstSectionY + CGFloat(index) * sectionHeight
    guard y < height - 100 else { break }

    let cardHeight = min(
      sectionHeight * 0.78,
      height - y - 80
    )
    let cardRect = CGRect(
      x: sidePadding,
      y: y,
      width: width - sidePadding * 2,
      height: cardHeight
    )
    let cardPath = CGPath(
      roundedRect: cardRect,
      cornerWidth: max(18, width * 0.025),
      cornerHeight: max(18, width * 0.025),
      transform: nil
    )
    context.setFillColor(
      NSColor.white.withAlphaComponent(index.isMultiple(of: 2) ? 0.92 : 0.82)
        .cgColor
    )
    context.addPath(cardPath)
    context.fillPath()

    drawText(
      String(format: "SECTION %02d", index + 1),
      at: CGPoint(
        x: sidePadding * 1.7,
        y: y + max(28, width * 0.04)
      ),
      fontSize: max(22, width * 0.035),
      weight: .bold,
      color: NSColor(calibratedWhite: 0.12, alpha: 1)
    )

    let lineStartY = y + max(92, width * 0.12)
    let lineHeight = max(13, width * 0.016)
    let lineGap = lineHeight * 1.8
    for lineIndex in 0..<5 {
      let lineWidthRatio = lineIndex == 4 ? 0.54 : 0.82 - CGFloat(lineIndex % 2) * 0.08
      let lineRect = CGRect(
        x: sidePadding * 1.7,
        y: lineStartY + CGFloat(lineIndex) * lineGap,
        width: cardRect.width * lineWidthRatio,
        height: lineHeight
      )
      context.setFillColor(
        NSColor(calibratedWhite: 0.28, alpha: 0.27).cgColor
      )
      context.fill(lineRect)
    }
  }
}

func drawRulers(_ specification: ImageSpec, in context: CGContext) {
  let width = CGFloat(specification.width)
  let height = CGFloat(specification.height)
  let interval = max(500, Int(width * 0.6))

  context.setStrokeColor(NSColor.white.withAlphaComponent(0.68).cgColor)
  context.setLineWidth(max(2, width * 0.002))

  for y in stride(from: interval, to: specification.height, by: interval) {
    let yValue = CGFloat(y)
    context.move(to: CGPoint(x: 0, y: yValue))
    context.addLine(to: CGPoint(x: width * 0.035, y: yValue))
    context.move(to: CGPoint(x: width * 0.965, y: yValue))
    context.addLine(to: CGPoint(x: width, y: yValue))
    context.strokePath()

    drawText(
      "\(y) px",
      at: CGPoint(
        x: width * 0.04,
        y: min(yValue + 8, height - 50)
      ),
      fontSize: max(14, width * 0.018),
      weight: .medium,
      color: NSColor.white.withAlphaComponent(0.78)
    )
  }
}

func drawFooter(_ specification: ImageSpec, in context: CGContext) {
  let width = CGFloat(specification.width)
  let height = CGFloat(specification.height)
  let footerHeight = min(260, max(150, width * 0.20))

  context.setFillColor(NSColor.black.withAlphaComponent(0.34).cgColor)
  context.fill(
    CGRect(
      x: 0,
      y: height - footerHeight,
      width: width,
      height: footerHeight
    )
  )
  drawText(
    "END OF \(specification.filename)",
    at: CGPoint(
      x: max(28, width * 0.055),
      y: height - footerHeight + max(45, width * 0.06)
    ),
    fontSize: max(20, width * 0.03),
    weight: .bold,
    color: .white
  )
}

func drawText(
  _ text: String,
  at point: CGPoint,
  fontSize: CGFloat,
  weight: NSFont.Weight,
  color: NSColor
) {
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
    .foregroundColor: color,
  ]
  text.draw(at: point, withAttributes: attributes)
}
