import Foundation

// Phase 1 prototype, not final release artwork. Run from the repository root:
// swift apps/macos/scripts/generate_app_icon.swift
// Icon Composer sources stay outside the app target; PNG slots support macOS 14.

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repository = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let source = repository.appendingPathComponent("assets/icon/CloakRoll.icon")
let catalogs = repository.appendingPathComponent("apps/macos/App/Resources/Assets.xcassets")

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
        throw CocoaError(.fileNoSuchFile)
    }
    let tool = URL(fileURLWithPath: path).deletingLastPathComponent()
        .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
    guard fileManager.isExecutableFile(atPath: tool.path) else {
        print("Icon Composer is required to regenerate artwork; select Xcode 26.4 or later.")
        throw CocoaError(.executableNotLoadable)
    }
    return tool
}

func writeCatalog(_ value: [String: Any], to folder: URL) throws {
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: folder.appendingPathComponent("Contents.json"), options: .atomic)
}

func exportIcon(tool: URL, size: Int, output: URL) throws {
    let process = Process()
    process.executableURL = tool
    process.arguments = [source.path, "--export-image", "--output-file", output.path,
                         "--platform", "macOS", "--rendition", "Default", "--width", String(size),
                         "--height", String(size), "--scale", "1", "--design-generation", "26"]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    print("Exported \(output.lastPathComponent)")
}

let iconTool = try activeIconTool()
let fallback = catalogs.appendingPathComponent("AppIcon.appiconset")
let about = catalogs.appendingPathComponent("AboutAppIcon.imageset")
let info: [String: Any] = ["author": "xcode", "version": 1]
let iconSlots = [16, 32, 128, 256, 512].flatMap { size in
    [1, 2].map { scale in
        ["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x",
         "filename": "icon_\(size * scale).png"]
    }
}
try writeCatalog(["images": iconSlots, "info": info], to: fallback)
try writeCatalog(["images": [
    ["idiom": "mac", "scale": "1x", "filename": "about_icon_256.png"],
    ["idiom": "mac", "scale": "2x", "filename": "about_icon_512.png"]
], "info": info], to: about)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try exportIcon(tool: iconTool, size: size, output: fallback.appendingPathComponent("icon_\(size).png"))
}
for size in [256, 512] {
    try exportIcon(tool: iconTool, size: size, output: about.appendingPathComponent("about_icon_\(size).png"))
}
