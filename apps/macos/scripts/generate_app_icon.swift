import Foundation
import ImageIO

// Run from any directory: swift apps/macos/scripts/generate_app_icon.swift
// Xcode compiles the layered launcher and its legacy fallback from CloakRoll.icon.
// This script exports native macOS 27 appearance previews and flattened About artwork.
// No committed output changes until every rendition renders and passes PNG validation.

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repository = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let source = repository.appendingPathComponent("assets/icon/CloakRoll.icon")
let about = repository.appendingPathComponent("apps/macos/App/Resources/Assets.xcassets/AboutAppIcon.imageset")
let previews = repository.appendingPathComponent("assets/icon/Previews")
let renditions = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]

enum IconExportError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): message }
    }
}

func activeIconTool() throws -> URL {
    let selection = Process()
    let pipe = Pipe()
    selection.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    selection.arguments = ["-p"]
    selection.standardOutput = pipe
    try selection.run()
    selection.waitUntilExit()
    let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard selection.terminationStatus == 0, !path.isEmpty else {
        throw IconExportError.failed("Select an Xcode installation containing Icon Composer.")
    }
    let tool = URL(fileURLWithPath: path).deletingLastPathComponent()
        .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
    guard fileManager.isExecutableFile(atPath: tool.path) else {
        throw IconExportError.failed("The selected Xcode has no Icon Composer exporter. macOS 27 design support is required.")
    }
    return tool
}

func validatePNG(_ url: URL, size: Int) throws {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetType(imageSource) as String? == "public.png",
          CGImageSourceGetCount(imageSource) == 1,
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
          image.width == size, image.height == size else {
        throw IconExportError.failed("Invalid PNG export: \(url.lastPathComponent); expected \(size) × \(size) pixels.")
    }
}

func exportIcon(tool: URL, rendition: String, size: Int, output: URL) throws {
    let process = Process()
    process.executableURL = tool
    process.arguments = [source.path, "--export-image", "--output-file", output.path,
                         "--platform", "macOS", "--rendition", rendition, "--width", String(size),
                         "--height", String(size), "--scale", "1", "--design-generation", "27"]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw IconExportError.failed("Icon Composer failed to export \(rendition) at \(size) pixels; existing artwork was retained.")
    }
    try validatePNG(output, size: size)
}

func generate() throws {
    guard fileManager.fileExists(atPath: source.appendingPathComponent("icon.json").path) else {
        throw IconExportError.failed("Missing icon source: \(source.path)")
    }
    let tool = try activeIconTool()
    let staging = fileManager.temporaryDirectory.appendingPathComponent("CloakRollIconExport-" + UUID().uuidString)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: staging) }
    let stagedPreviews = staging.appendingPathComponent("Previews")
    let stagedAbout = staging.appendingPathComponent("AboutAppIcon.imageset")
    for folder in [stagedPreviews, stagedAbout] {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    var outputs: [(staged: URL, final: URL)] = []
    for rendition in renditions {
        let name = "\(rendition)-512.png"
        let output = stagedPreviews.appendingPathComponent(name)
        try exportIcon(tool: tool, rendition: rendition, size: 512, output: output)
        outputs.append((output, previews.appendingPathComponent(name)))
    }
    for size in [16, 32, 64, 128] {
        let name = "Default-\(size).png"
        let output = stagedPreviews.appendingPathComponent(name)
        try exportIcon(tool: tool, rendition: "Default", size: size, output: output)
        outputs.append((output, previews.appendingPathComponent(name)))
    }
    var images: [[String: Any]] = []
    for rendition in ["Default", "Dark"] {
        for (scale, size) in [(1, 256), (2, 512)] {
            let name = "about_icon_\(rendition == "Dark" ? "dark_" : "")\(size).png"
            let output = stagedAbout.appendingPathComponent(name)
            if size == 512 {
                try fileManager.copyItem(at: stagedPreviews.appendingPathComponent("\(rendition)-512.png"), to: output)
                try validatePNG(output, size: size)
            } else {
                try exportIcon(tool: tool, rendition: rendition, size: size, output: output)
            }
            var item: [String: Any] = ["idiom": "mac", "scale": "\(scale)x", "filename": name]
            if rendition == "Dark" { item["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
            images.append(item)
            outputs.append((output, about.appendingPathComponent(name)))
        }
    }
    let contents = try JSONSerialization.data(withJSONObject: [
        "images": images, "info": ["author": "xcode", "version": 1]
    ], options: [.prettyPrinted, .sortedKeys])
    let stagedContents = stagedAbout.appendingPathComponent("Contents.json")
    try contents.write(to: stagedContents)
    // Publish catalog metadata last, after all referenced images have been replaced.
    outputs.append((stagedContents, about.appendingPathComponent("Contents.json")))
    for output in outputs {
        try fileManager.createDirectory(at: output.final.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: output.staged).write(to: output.final, options: .atomic)
    }
    print("Exported six macOS 27 appearances, four small-size previews, and Default/Dark About artwork.")
}

try generate()
