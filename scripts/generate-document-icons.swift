import AppKit
import CoreText
import Foundation

struct DocumentIconSpec {
    let fileStem: String
    let svgName: String
    let letters: [String]
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let svgDirectory = resources.appendingPathComponent("DocumentIcons", isDirectory: true)
try FileManager.default.createDirectory(at: svgDirectory, withIntermediateDirectories: true)

let specs = [
    DocumentIconSpec(fileStem: "SingleVoiceDocumentIcon", svgName: "single-voice-document.svg", letters: ["V"]),
    DocumentIconSpec(fileStem: "SingleConfigurationDocumentIcon", svgName: "single-configuration-document.svg", letters: ["C"]),
    DocumentIconSpec(fileStem: "VoiceBankDocumentIcon", svgName: "voice-bank-document.svg", letters: ["V", "V", "V"]),
    DocumentIconSpec(fileStem: "ConfigurationBankDocumentIcon", svgName: "configuration-bank-document.svg", letters: ["C", "C", "C"]),
]

let iconSizes = [
    (16, false), (16, true),
    (32, false), (32, true),
    (128, false), (128, true),
    (256, false), (256, true),
    (512, false), (512, true),
]

func drawIcon(spec: DocumentIconSpec, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let scale = size / 1024
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let pageRect = NSRect(x: 176 * scale, y: 92 * scale, width: 672 * scale, height: 840 * scale)
    let pagePath = NSBezierPath(roundedRect: pageRect, xRadius: 90 * scale, yRadius: 90 * scale)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    pagePath.fill()
    NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
    pagePath.lineWidth = 18 * scale
    pagePath.stroke()

    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: 702 * scale, y: 932 * scale))
    foldPath.line(to: NSPoint(x: 848 * scale, y: 786 * scale))
    foldPath.line(to: NSPoint(x: 702 * scale, y: 786 * scale))
    foldPath.close()
    NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
    foldPath.fill()
    NSColor(calibratedWhite: 0.70, alpha: 1).setStroke()
    foldPath.lineWidth = 12 * scale
    foldPath.stroke()

    drawLetters(spec.letters, scale: scale)
    drawFB01Base(scale: scale)

    return image
}

func drawLetters(_ letters: [String], scale: CGFloat) {
    let blue = NSColor(calibratedRed: 0.0, green: 0.56, blue: 1.0, alpha: 1.0)

    if letters.count == 1 {
        drawGlyph(letters[0], fontSize: 430 * scale, centerX: 512 * scale, bottomY: 302 * scale, color: blue)
        return
    }

    let positions = [
        (letters[0], 300 * scale, 322 * scale),
        (letters[1], 512 * scale, 410 * scale),
        (letters[2], 724 * scale, 322 * scale),
    ]
    for (letter, centerX, bottomY) in positions {
        drawGlyph(letter, fontSize: 300 * scale, centerX: centerX, bottomY: bottomY, color: blue)
    }
}

func drawGlyph(_ string: String, fontSize: CGFloat, centerX: CGFloat, bottomY: CGFloat, color: NSColor) {
    guard let scalar = string.unicodeScalars.first else { return }
    let font = CTFontCreateWithName(NSFont.boldSystemFont(ofSize: fontSize).fontName as CFString, fontSize, nil)
    var character = UniChar(scalar.value)
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
          let cgPath = CTFontCreatePathForGlyph(font, glyph, nil) else {
        return
    }

    let path = NSBezierPath(cgPath: cgPath)
    let bounds = path.bounds
    var transform = AffineTransform()
    transform.translate(
        x: centerX - bounds.midX,
        y: bottomY - bounds.minY
    )
    path.transform(using: transform)
    color.setFill()
    path.fill()
}

func drawFB01Base(scale: CGFloat) {
    let baseRect = NSRect(x: 250 * scale, y: 176 * scale, width: 524 * scale, height: 130 * scale)
    let base = NSBezierPath(roundedRect: baseRect, xRadius: 18 * scale, yRadius: 18 * scale)
    NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.03, alpha: 1).setFill()
    base.fill()

    let screen = NSBezierPath(roundedRect: NSRect(x: 305 * scale, y: 218 * scale, width: 205 * scale, height: 42 * scale), xRadius: 8 * scale, yRadius: 8 * scale)
    NSColor(calibratedRed: 1.0, green: 0.44, blue: 0.02, alpha: 1).setFill()
    screen.fill()

    NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
    for column in 0..<3 {
        for row in 0..<2 {
            let x = CGFloat(568 + column * 54) * scale
            let y = CGFloat(212 + row * 36) * scale
            let rect = NSRect(x: x, y: y, width: 32 * scale, height: 18 * scale)
            NSBezierPath(roundedRect: rect, xRadius: 4 * scale, yRadius: 4 * scale).fill()
        }
    }
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

func writeSVG(spec: DocumentIconSpec) throws {
    let letterMarkup: String
    if spec.letters.count == 1 {
        letterMarkup = "<text x=\"512\" y=\"718\" text-anchor=\"middle\" font-family=\"-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif\" font-size=\"430\" font-weight=\"800\" fill=\"#008FFF\">\(spec.letters[0])</text>"
    } else {
        letterMarkup = zip(spec.letters, [(300, 706), (512, 618), (724, 706)])
            .map { letter, point in "<text x=\"\(point.0)\" y=\"\(point.1)\" text-anchor=\"middle\" font-family=\"-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif\" font-size=\"300\" font-weight=\"800\" fill=\"#008FFF\">\(letter)</text>" }
            .joined(separator: "\n  ")
    }

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
      <rect width="1024" height="1024" fill="none"/>
      <rect x="176" y="92" width="672" height="840" rx="90" fill="#F7F7F7" stroke="#B8B8B8" stroke-width="18"/>
      <path d="M702 932 L848 786 L702 786 Z" fill="#E0E0E0" stroke="#B3B3B3" stroke-width="12"/>
      \(letterMarkup)
      <rect x="250" y="718" width="524" height="130" rx="18" fill="#050607"/>
      <rect x="305" y="764" width="205" height="42" rx="8" fill="#FF7005"/>
      <g fill="#333333">
        <rect x="568" y="776" width="32" height="18" rx="4"/>
        <rect x="622" y="776" width="32" height="18" rx="4"/>
        <rect x="676" y="776" width="32" height="18" rx="4"/>
        <rect x="568" y="740" width="32" height="18" rx="4"/>
        <rect x="622" y="740" width="32" height="18" rx="4"/>
        <rect x="676" y="740" width="32" height="18" rx="4"/>
      </g>
    </svg>
    """
    try svg.write(to: svgDirectory.appendingPathComponent(spec.svgName), atomically: true, encoding: .utf8)
}

for spec in specs {
    try writeSVG(spec: spec)
    let iconset = resources.appendingPathComponent("\(spec.fileStem).iconset", isDirectory: true)
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for (points, isRetina) in iconSizes {
        let pixels = points * (isRetina ? 2 : 1)
        let suffix = isRetina ? "@2x" : ""
        let image = drawIcon(spec: spec, size: CGFloat(pixels))
        try writePNG(image, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }

    let icns = resources.appendingPathComponent("\(spec.fileStem).icns")
    try? FileManager.default.removeItem(at: icns)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    try FileManager.default.removeItem(at: iconset)
}
