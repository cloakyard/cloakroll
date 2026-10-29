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

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat, hex: UInt32) {
    color(hex).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h),
                 xRadius: radius, yRadius: radius).fill()
}

func flower(_ x: CGFloat, _ y: CGFloat, size: CGFloat, petals: UInt32, center: UInt32) {
    for petal in 0..<8 {
        let angle = CGFloat(petal) * .pi / 4
        oval(x + cos(angle) * size * 0.28 - size * 0.22,
             y + sin(angle) * size * 0.28 - size * 0.22, size * 0.44, size * 0.44, petals)
    }
    oval(x - size * 0.17, y - size * 0.17, size * 0.34, size * 0.34, center)
}

func flowers() {
    sky(0xF1E6D8, 0xE6CDC1)
    rect(0, 375, 640, 105, 0xD8BDAA)
    oval(213, 411, 216, 29, 0xBEA499, alpha: 0.45)
    curve((315, 340), [(281, 272, 252, 224, 260, 164)], fill: 0x648775, close: false, strokeWidth: 7)
    curve((322, 338), [(340, 255, 355, 178, 346, 113)], fill: 0x648775, close: false, strokeWidth: 6)
    curve((329, 337), [(363, 302, 389, 267, 404, 221)], fill: 0x648775, close: false, strokeWidth: 6)
    oval(229, 246, 70, 26, 0x91AA89)
    oval(340, 266, 73, 28, 0x7B997E)
    oval(310, 209, 36, 67, 0xA7B69A)
    flower(260, 168, size: 152, petals: 0xC88A91, center: 0xEFD19B)
    flower(346, 115, size: 117, petals: 0xE4B46F, center: 0xF5E1B7)
    flower(407, 220, size: 111, petals: 0xDCB5AD, center: 0xBC8C76)
    roundedRect(250, 292, 141, 135, radius: 28, hex: 0x74958C)
    rect(250, 282, 141, 40, 0x74958C)
    oval(250, 270, 141, 25, 0xA5BCAC)
    curve((273, 311), [(269, 350, 275, 389, 284, 402)], fill: 0x95B0A2, close: false, strokeWidth: 6)
}

func cafe() {
    sky(0xEBD8C7, 0xDABAA8)
    polygon([(91, 42), (509, 62), (550, 431), (117, 458)], 0xF0E4D4)
    roundedRect(110, 309, 107, 122, radius: 8, hex: 0x7D9793)
    rect(119, 309, 3, 122, 0x637F7C)
    for line in 0..<3 { rect(138, 336 + CGFloat(line) * 12, 57, 2, 0xBEC8B5) }
    oval(203, 138, 276, 245, 0xCBBBAD)
    oval(184, 110, 276, 245, 0xB7C8C4)
    oval(201, 124, 244, 215, 0xD2DCD3)
    oval(396, 176, 81, 100, 0xFCF3E3)
    oval(416, 194, 42, 64, 0xD2DCD3)
    oval(222, 137, 198, 198, 0xFFF5E3)
    oval(238, 153, 166, 166, 0x9B6F55)
    oval(247, 161, 147, 146, 0xB28664)
    let heart = NSBezierPath()
    heart.move(to: NSPoint(x: 321, y: 276))
    heart.curve(to: NSPoint(x: 321, y: 218), controlPoint1: NSPoint(x: 240, y: 208), controlPoint2: NSPoint(x: 296, y: 186))
    heart.curve(to: NSPoint(x: 321, y: 276), controlPoint1: NSPoint(x: 350, y: 183), controlPoint2: NSPoint(x: 401, y: 221))
    color(0xF6DEB6).setFill()
    heart.fill()
    let pastry = NSBezierPath()
    pastry.move(to: NSPoint(x: 329, y: 400))
    pastry.curve(to: NSPoint(x: 512, y: 396), controlPoint1: NSPoint(x: 348, y: 308), controlPoint2: NSPoint(x: 481, y: 303))
    pastry.curve(to: NSPoint(x: 329, y: 400), controlPoint1: NSPoint(x: 445, y: 368), controlPoint2: NSPoint(x: 393, y: 369))
    pastry.close()
    color(0xCA9564).setFill()
    pastry.fill()
    for x in [378.0, 412.0, 446.0] {
        curve((x, 340), [(x - 10, 351, x - 8, 364, x + 4, 378)], fill: 0xE7B77D, close: false, strokeWidth: 8)
    }
}

func arch(_ x: CGFloat, _ bottom: CGFloat, width: CGFloat, top: CGFloat, fill: UInt32) {
    let radius = width / 2
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: bottom))
    path.line(to: NSPoint(x: x, y: top + radius))
    path.curve(to: NSPoint(x: x + width, y: top + radius),
               controlPoint1: NSPoint(x: x, y: top - radius / 3),
               controlPoint2: NSPoint(x: x + width, y: top - radius / 3))
    path.line(to: NSPoint(x: x + width, y: bottom))
    path.close()
    color(fill).setFill()
    path.fill()
}

func courtyard() {
    sky(0xE6C9AD, 0xD8AA91)
    rect(0, 418, 640, 62, 0xBA9585)
    rect(0, 449, 640, 2, 0xD4B49B)
    arch(197, 419, width: 246, top: 87, fill: 0xF0D9B8)
    arch(222, 419, width: 196, top: 113, fill: 0x547B7B)
    rect(237, 242, 166, 3, 0x82A09A)
    rect(318, 144, 3, 273, 0x82A09A)
    for x in [247.0, 340.0] {
        roundedRect(x, 263, 48, 116, radius: 4, hex: 0x426767)
    }
    oval(328, 297, 9, 9, 0xD8B378)
    rect(112, 180, 62, 93, 0xF0D9B8)
    rect(120, 188, 46, 77, 0x7F9491)
    rect(141, 188, 3, 77, 0xE4C9A6)
    for (x, y, size) in [(148.0, 333.0, 1.0), (484.0, 347.0, 0.84)] {
        rect(x - 3, y - 44, 6, 97, 0x6A8266)
        oval(x - 48 * size, y - 43 * size, 48 * size, 25 * size, 0x789779)
        oval(x + 2, y - 64 * size, 43 * size, 25 * size, 0x91A17F)
        oval(x - 19 * size, y - 94 * size, 29 * size, 51 * size, 0x607D65)
        polygon([(x - 35, y + 9), (x + 35, y + 9), (x + 26, 423), (x - 26, 423)], 0xB77E65)
        roundedRect(x - 39, y + 3, 78, 14, radius: 4, hex: 0xD09B7D)
    }
}

func restingDog() {
    sky(0xD4DFDA, 0xBBCED0)
    rect(425, 0, 112, 149, 0xEDF0E4)
    rect(479, 0, 5, 149, 0xB8C9C5)
    rect(425, 72, 112, 5, 0xB8C9C5)
    oval(74, 240, 500, 212, 0x809BA9)
    oval(96, 228, 456, 182, 0x99AEB8)
    curve((432, 292), [(486, 291, 507, 253, 484, 226)], fill: 0xC99F7C, close: false, strokeWidth: 29)
    oval(235, 209, 233, 147, 0xD8B18B)
    oval(299, 223, 146, 117, 0xE5C29C)
    oval(231, 257, 100, 96, 0xF0D7B5)
    oval(203, 319, 100, 38, 0xF0D7B5)
    oval(337, 324, 92, 36, 0xEACAA6)
    roundedRect(226, 283, 91, 19, radius: 9, hex: 0x618F87)
    oval(264, 295, 18, 22, 0xE3BB76)
    // Soft, hanging ears and a broad muzzle distinguish the puppy at thumbnail size.
    oval(174, 177, 56, 116, 0xB78D70)
    oval(305, 177, 54, 113, 0xB78D70)
    oval(195, 154, 143, 145, 0xE8C59D)
    oval(216, 231, 103, 64, 0xF6DDBA)
    oval(231, 211, 13, 17, 0x514840)
    oval(288, 211, 13, 17, 0x514840)
    oval(234, 213, 4, 5, 0xFFF7E7)
    oval(291, 213, 4, 5, 0xFFF7E7)
    oval(254, 241, 26, 18, 0x66534A)
    oval(258, 243, 8, 4, 0x9C8371)
    roundedRect(262, 272, 17, 23, radius: 8, hex: 0xCF9690)
    curve((267, 256), [(267, 275, 250, 278, 244, 269)], fill: 0x8C6C57, close: false, strokeWidth: 3)
    curve((267, 256), [(267, 275, 283, 278, 289, 269)], fill: 0x8C6C57, close: false, strokeWidth: 3)
    for x in [228.0, 243.0, 361.0, 376.0] {
        curve((x, 341), [(x - 2, 345, x - 2, 350, x, 353)], fill: 0xC6A688, close: false, strokeWidth: 2)
    }
}

func citrus() {
    sky(0xECE6D3, 0xDED4B8)
    oval(159, 96, 336, 309, 0xC6BDA3)
    oval(145, 82, 336, 309, 0x98B5A7)
    oval(166, 103, 294, 266, 0xBDD0B8)
    oval(235, 133, 137, 137, 0xDEA264)
    oval(249, 143, 104, 101, 0xE8B775)
    oval(291, 128, 34, 14, 0x608368)
    oval(344, 239, 126, 89, 0xE4C567)
    oval(356, 245, 100, 66, 0xF1D88D)
    oval(390, 212, 65, 26, 0x648C72)
    oval(194, 276, 143, 143, 0xD7955E)
    oval(201, 283, 129, 129, 0xF4E4BE)
    for segment in 0..<8 {
        let a = CGFloat(segment) * .pi / 4 + 0.06
        let b = a + .pi / 4 - 0.12
        let mid = (a + b) / 2
        polygon([(266 + cos(mid) * 8, 348 + sin(mid) * 8),
                 (266 + cos(a) * 55, 348 + sin(a) * 55),
                 (266 + cos(mid) * 58, 348 + sin(mid) * 58),
                 (266 + cos(b) * 55, 348 + sin(b) * 55)], segment % 2 == 0 ? 0xE8B072 : 0xDE9C60)
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
        polygon([(391, 264), (475, 264), (458, 282), (408, 282)], 0x436775)
        polygon([(434, 157), (434, 255), (380, 255)], 0xF7EFDC)
        polygon([(441, 186), (482, 255), (441, 255)], 0xD9E5D9)
    case 2:
        flowers()
    case 3:
        cafe()
    case 4:
        courtyard()
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
    case 6:
        restingDog()
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
    case 9:
        citrus()
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
