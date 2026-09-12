import AppKit
import Foundation

// Deterministic, original vector illustrations for the mock library. These are not photographs
// or representations of user media. Run: swift apps/macos/scripts/generate_sample_art.swift

let width = 640
let height = 480
let script = URL(fileURLWithPath: #filePath).standardizedFileURL
let repository = script.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let catalog = repository.appendingPathComponent("apps/macos/App/Resources/Assets.xcassets")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32) {
    color(hex).setFill()
    NSBezierPath(rect: NSRect(x: x, y: y, width: w, height: h)).fill()
}

func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, alpha: CGFloat = 1) {
    color(hex, alpha: alpha).setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h)).fill()
}

func polygon(_ points: [(CGFloat, CGFloat)], _ hex: UInt32, alpha: CGFloat = 1) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: NSPoint(x: first.0, y: first.1))
    for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
    path.close()
    color(hex, alpha: alpha).setFill()
    path.fill()
}

func curve(_ start: (CGFloat, CGFloat), _ segments: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)],
           fill hex: UInt32, close: Bool = true, strokeWidth: CGFloat = 0) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: start.0, y: start.1))
    for segment in segments {
        path.curve(to: NSPoint(x: segment.4, y: segment.5),
                   controlPoint1: NSPoint(x: segment.0, y: segment.1),
                   controlPoint2: NSPoint(x: segment.2, y: segment.3))
    }
    if close {
        path.line(to: NSPoint(x: 660, y: 500))
        path.line(to: NSPoint(x: -20, y: 500))
        path.close()
        color(hex).setFill()
        path.fill()
    } else {
        color(hex).setStroke()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.stroke()
    }
}

func sky(_ top: UInt32, _ bottom: UInt32) {
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    if let gradient = NSGradient(starting: color(top), ending: color(bottom)) {
        gradient.draw(in: NSBezierPath(rect: bounds), angle: 90)
    }
}

func cloud(_ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1, hex: UInt32 = 0xFFF5EA) {
    oval(x, y + 11 * scale, 91 * scale, 14 * scale, hex, alpha: 0.6)
    oval(x + 12 * scale, y + 1 * scale, 42 * scale, 30 * scale, hex, alpha: 0.6)
    oval(x + 36 * scale, y - 5 * scale, 39 * scale, 34 * scale, hex, alpha: 0.6)
}

func pine(_ x: CGFloat, _ y: CGFloat, size: CGFloat, hex: UInt32) {
    rect(x - size * 0.025, y - size * 0.17, size * 0.05, size * 0.22, hex)
    polygon([(x, y - size), (x - size * 0.21, y - size * 0.55), (x - size * 0.12, y - size * 0.55),
             (x - size * 0.29, y - size * 0.25), (x - size * 0.16, y - size * 0.25),
             (x - size * 0.35, y), (x + size * 0.35, y), (x + size * 0.16, y - size * 0.25),
             (x + size * 0.29, y - size * 0.25), (x + size * 0.12, y - size * 0.55),
             (x + size * 0.21, y - size * 0.55)], hex)
}

func waterLines(_ hex: UInt32, from y: CGFloat, count: Int = 8) {
    for line in 0..<count {
        let offset = CGFloat(line)
        let x = CGFloat((line * 137 + 37) % 560)
        curve((x, y + offset * 17), [(x + 20, y + offset * 17 - 2,
                                     x + 50, y + offset * 17 + 2,
                                     x + 80, y + offset * 17)], fill: hex, close: false, strokeWidth: 2)
    }
}

func drawScene(_ index: Int) {
    switch index {
    case 0: // Quiet alpine dawn.
        sky(0xB6A5D7, 0xF7D1B4)
        oval(438, 61, 89, 89, 0xFFE5B4)
        polygon([(-20, 302), (105, 136), (212, 276), (357, 100), (527, 283), (640, 167), (660, 390)], 0x9B89B0)
        polygon([(276, 196), (357, 100), (440, 191), (376, 166), (350, 180), (332, 158)], 0xEADAE8)
        polygon([(-20, 340), (123, 243), (247, 328), (415, 226), (580, 336), (660, 285), (660, 500), (-20, 500)], 0x746B9B)
        rect(0, 329, 640, 151, 0xB3A3CB)
        waterLines(0xD6C2DC, from: 351)
        curve((-20, 400), [(95, 365, 176, 444, 283, 466), (403, 483, 506, 395, 660, 426)], fill: 0x474765)
        pine(90, 450, size: 108, hex: 0x353C54)
        pine(132, 470, size: 76, hex: 0x353C54)
    case 1: // Sunlit coastal path.
        sky(0x9CCFDD, 0xEAE8D0)
        oval(452, 64, 71, 71, 0xFFF1CE)
        cloud(72, 86, scale: 1.2)
        rect(0, 221, 640, 259, 0x58ADBC)
        rect(0, 271, 640, 209, 0x4B9EAB)
        curve((-20, 299), [(189, 231, 235, 370, 404, 378), (516, 389, 586, 351, 660, 362)], fill: 0xDAD8B8)
        curve((-20, 320), [(111, 280, 127, 360, 257, 400), (330, 426, 408, 434, 460, 500)], fill: 0xF2D8AF)
        polygon([(-20, 245), (92, 189), (137, 207), (198, 197), (255, 277), (196, 350), (106, 369), (-20, 400)], 0xA2AB8F)
        polygon([(-20, 243), (90, 189), (137, 207), (198, 197), (170, 252), (58, 267), (-20, 300)], 0x647F70)
        curve((222, 350), [(337, 394, 465, 411, 629, 390)], fill: 0xECEDDA, close: false, strokeWidth: 5)
        waterLines(0x9BCBC6, from: 281, count: 4)
    case 2: // Forest in morning mist.
        sky(0xBCCDC6, 0xEFE7C6)
        oval(130, 95, 94, 94, 0xF6E5AF)
        curve((-20, 299), [(172, 184, 290, 259, 410, 188), (522, 152, 590, 229, 660, 224)], fill: 0xA5B9AB)
        curve((-20, 372), [(96, 319, 182, 349, 329, 263), (417, 211, 580, 296, 660, 268)], fill: 0x7D9D92)
        for tree in 0..<14 {
            pine(CGFloat(tree * 51 - 15), 388 + CGFloat(tree % 3) * 10,
                 size: 93 + CGFloat(tree % 4) * 25, hex: 0x5B8178)
        }
        curve((-20, 408), [(189, 363, 290, 426, 458, 381), (575, 349, 628, 374, 660, 368)], fill: 0xA8BEB0)
        for tree in [0, 1, 2, 10, 12, 13] {
            pine(CGFloat(tree * 51), 495, size: 164 + CGFloat(tree % 3) * 24, hex: 0x315D57)
        }
    case 3: // Warm, unmarked dunes.
        sky(0xDCAAAC, 0xF7D3B0)
        oval(385, 72, 121, 121, 0xFFE3B6)
        curve((-20, 300), [(155, 278, 298, 172, 444, 232), (535, 273, 597, 250, 660, 242)], fill: 0xD3A0A0)
        curve((-20, 354), [(202, 356, 300, 205, 483, 274), (562, 306, 621, 322, 660, 314)], fill: 0xEFC19F)
        curve((-20, 393), [(118, 307, 197, 322, 332, 373), (474, 425, 552, 371, 660, 360)], fill: 0xD5917C)
        curve((-20, 450), [(119, 431, 230, 362, 405, 408), (517, 438, 607, 463, 660, 452)], fill: 0xA96870)
        curve((107, 353), [(218, 329, 278, 358, 383, 390)], fill: 0xF1C4A1, close: false, strokeWidth: 3)
    case 4: // Lavender and a tiny farmhouse.
        sky(0xC3C4E2, 0xF0D5CB)
        cloud(83, 93, scale: 1.2)
        cloud(409, 133, scale: 0.75)
        curve((-20, 274), [(158, 198, 303, 255, 435, 217), (536, 196, 599, 237, 660, 235)], fill: 0x969DBB)
        curve((-20, 338), [(170, 269, 305, 298, 441, 273), (535, 252, 615, 275, 660, 269)], fill: 0x879576)
        rect(414, 261, 61, 40, 0xEADAB8)
        polygon([(405, 262), (444, 238), (484, 262)], 0x817273)
        rect(437, 281, 10, 20, 0x646B67)
        curve((-20, 342), [(194, 289, 396, 349, 660, 303)], fill: 0xBC9CC4)
        for row in 0..<8 {
            let x = CGFloat(row * 95 - 40)
            polygon([(345 + CGFloat(row) * 6, 322), (357 + CGFloat(row) * 7, 322),
                     (x + 53, 500), (x, 500)], row % 2 == 0 ? 0x8C72A6 : 0xA186B5)
        }
        pine(497, 304, size: 66, hex: 0x586A62)
    case 5: // A small island at golden hour.
        sky(0xDEB2B8, 0xF6DDBB)
        oval(275, 61, 100, 100, 0xFFE8C0)
        rect(0, 229, 640, 251, 0x81BABD)
        rect(0, 290, 640, 190, 0x6BA7AC)
        oval(281, 257, 100, 8, 0xD6D3B6, alpha: 0.7)
        oval(264, 284, 142, 7, 0xCCD1B9, alpha: 0.5)
        curve((168, 314), [(259, 294, 304, 229, 363, 261), (404, 284, 435, 298, 481, 314)], fill: 0xE2CFAF)
        polygon([(188, 312), (302, 243), (342, 222), (371, 271), (434, 305)], 0x527B74)
        polygon([(301, 284), (342, 222), (371, 271), (434, 305)], 0x396B69)
        rect(0, 336, 640, 144, 0x6BA7AC)
        waterLines(0xA5C7BF, from: 352)
        curve((-20, 457), [(109, 414, 150, 446, 265, 475), (350, 502, 493, 436, 660, 445)], fill: 0x397F88)
    case 6: // High alpine snow.
        sky(0x86B5D2, 0xC9DDE1)
        cloud(409, 75, scale: 1.3, hex: 0xEFF5F2)
        polygon([(-20, 386), (145, 160), (278, 318), (401, 83), (660, 381), (660, 500), (-20, 500)], 0x6E91AB)
        polygon([(297, 267), (401, 83), (513, 219), (449, 200), (403, 173), (379, 212), (359, 192)], 0xF0F0E9)
        polygon([(55, 287), (145, 160), (241, 277), (164, 229), (138, 245), (121, 218)], 0xDCE8E6)
        polygon([(401, 83), (418, 229), (536, 357), (660, 381)], 0x4D7593)
        polygon([(401, 83), (418, 229), (449, 200)], 0xCADCDD)
        curve((-20, 391), [(108, 369, 183, 391, 328, 348), (469, 306, 564, 386, 660, 336)], fill: 0xD1E2E1)
        curve((-20, 470), [(109, 409, 178, 442, 270, 414), (406, 369, 478, 450, 660, 410)], fill: 0x9FBCC4)
        pine(82, 475, size: 116, hex: 0x466879)
        pine(128, 483, size: 78, hex: 0x466879)
    case 7: // Evening river and an invented skyline.
        sky(0x777497, 0xE8B6A5)
        oval(431, 119, 91, 91, 0xF3CAA9)
        rect(0, 318, 640, 162, 0xB697B2)
        let buildings: [(CGFloat, CGFloat, CGFloat)] = [(16, 251, 65), (76, 223, 46), (129, 270, 39),
            (179, 186, 49), (238, 240, 57), (303, 165, 52), (365, 224, 62), (437, 256, 48),
            (494, 208, 52), (555, 266, 77)]
        for (x, y, w) in buildings {
            rect(x, y, w, 321 - y, 0x655F7B)
            rect(x + 6, y + 8, w - 12, 2, 0x8A7991)
            for floor in 0..<4 where y + CGFloat(floor) * 20 + 20 < 307 {
                rect(x + 11, y + CGFloat(floor) * 20 + 15, 5, 7, 0xE2BEA8)
                rect(x + w - 17, y + CGFloat(floor) * 20 + 15, 5, 7, 0xB6A0AA)
            }
        }
        polygon([(303, 165), (329, 137), (355, 165)], 0x655F7B)
        waterLines(0xCCB1BF, from: 339)
        curve((-20, 410), [(185, 378, 426, 378, 660, 412)], fill: 0x514F6B, close: false, strokeWidth: 13)
        for column in 0..<8 { rect(CGFloat(column * 90 + 6), 403, 8, 77, 0x514F6B) }
        curve((-20, 435), [(169, 458, 230, 474, 311, 500)], fill: 0x44465F)
    case 8: // Moon above a desert mesa.
        sky(0x343950, 0x817693)
        oval(451, 64, 78, 78, 0xE7DFC5)
        oval(473, 50, 69, 78, 0x414258)
        for star in 0..<37 {
            let x = CGFloat((star * 173 + 41) % 620 + 10)
            let y = CGFloat((star * 71 + 23) % 210 + 15)
            oval(x, y, star % 5 == 0 ? 3 : 2, star % 5 == 0 ? 3 : 2, 0xECE3D4, alpha: 0.65)
        }
        polygon([(-20, 349), (79, 287), (100, 228), (180, 226), (201, 291), (301, 332),
                 (365, 256), (374, 203), (440, 202), (465, 294), (660, 348), (660, 500), (-20, 500)], 0x947587)
        polygon([(80, 286), (100, 228), (122, 228), (128, 310), (202, 338)], 0xB2898D)
        curve((-20, 370), [(148, 338, 242, 420, 429, 353), (548, 311, 584, 383, 660, 376)], fill: 0x674F69)
        curve((-20, 449), [(117, 388, 203, 407, 340, 455), (500, 507, 531, 397, 660, 411)], fill: 0x403F58)
    case 9: // Autumn reflected in a lake.
        sky(0xD7C8BF, 0xFAE2B9)
        oval(135, 65, 84, 84, 0xF7E8BD)
        curve((-20, 275), [(163, 155, 265, 277, 445, 213), (561, 169, 614, 229, 660, 236)], fill: 0xBD9995)
        curve((-20, 317), [(109, 287, 205, 265, 372, 288), (506, 308, 547, 233, 660, 266)], fill: 0x9A767D)
        rect(0, 313, 640, 167, 0xB9B3BB)
        waterLines(0xDED0C9, from: 337)
        curve((-20, 415), [(127, 355, 177, 424, 292, 425), (458, 418, 561, 433, 660, 387)], fill: 0x776E70)
        for tree in 0..<6 {
            let x = CGFloat(tree * 49 - 7)
            let y = CGFloat(329 + tree % 3 * 23)
            rect(x + 16, y + 33, 5, 68, 0x6D5F66)
            oval(x - 14, y - 17, 68, 81, tree % 2 == 0 ? 0xCF8E68 : 0xB97267)
            oval(x - 21, y + 14, 57, 50, tree % 2 == 0 ? 0xD8A06F : 0xC18069)
        }
    case 10: // A green valley after rain.
        sky(0xB5D0C9, 0xEFE0B6)
        cloud(373, 77, scale: 1.35)
        cloud(87, 125, scale: 0.8)
        curve((-20, 303), [(188, 139, 304, 289, 434, 214), (555, 143, 591, 247, 660, 216)], fill: 0x95AA96)
        curve((-20, 364), [(108, 273, 213, 232, 361, 317), (480, 381, 568, 254, 660, 285)], fill: 0x74967A)
        curve((-20, 419), [(187, 337, 294, 437, 405, 376), (514, 316, 594, 356, 660, 324)], fill: 0x547A65)
        curve((331, 323), [(413, 354, 244, 366, 302, 391), (399, 425, 405, 469, 248, 500)], fill: 0xABC8BE,
              close: false, strokeWidth: 19)
        rect(129, 303, 55, 40, 0xE6D8B7)
        polygon([(120, 304), (156, 278), (193, 304)], 0x967B6F)
        rect(147, 322, 11, 21, 0x6A7167)
        pine(108, 347, size: 69, hex: 0x436C5D)
        pine(562, 475, size: 151, hex: 0x325D51)
    default: // Sandstone canyon and a distant river.
        sky(0xBCA4B4, 0xF3CAB2)
        oval(282, 88, 79, 79, 0xF9DAB9)
        polygon([(-20, 304), (90, 218), (151, 244), (211, 217), (281, 291), (345, 231),
                 (437, 264), (530, 224), (660, 304), (660, 500), (-20, 500)], 0xB78D98)
        polygon([(-20, 195), (115, 216), (139, 248), (112, 285), (181, 340), (241, 357),
                 (255, 430), (151, 500), (-20, 500)], 0xCB998A)
        polygon([(660, 180), (533, 205), (515, 252), (558, 275), (474, 334), (407, 378),
                 (391, 435), (455, 500), (660, 500)], 0xA76E78)
        curve((327, 314), [(362, 349, 290, 366, 330, 400), (399, 443, 363, 462, 328, 500)],
              fill: 0x9DB8B5, close: false, strokeWidth: 16)
        curve((-20, 316), [(61, 297, 94, 348, 162, 350)], fill: 0xDEB29B, close: false, strokeWidth: 12)
        curve((480, 366), [(535, 346, 574, 313, 660, 316)], fill: 0xCA9188, close: false, strokeWidth: 12)
        polygon([(-20, 424), (86, 390), (184, 446), (201, 500), (-20, 500)], 0x8C6973)
        polygon([(660, 407), (542, 389), (447, 480), (444, 500), (660, 500)], 0x735C6C)
    }
}

for index in 0..<12 {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    let flip = AffineTransform(translationByX: 0, byY: CGFloat(height))
    let transform = NSAffineTransform(transform: flip)
    transform.scaleX(by: 1, yBy: -1)
    transform.concat()
    drawScene(index)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let folder = catalog.appendingPathComponent("Sample\(index).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent("sample_\(index).png"), options: .atomic)
    let contents: [String: Any] = [
        "images": [["idiom": "universal", "filename": "sample_\(index).png"]],
        "info": ["author": "xcode", "version": 1]
    ]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: folder.appendingPathComponent("Contents.json"), options: .atomic)
    print("Rendered Sample\(index) (\(width)×\(height))")
}
