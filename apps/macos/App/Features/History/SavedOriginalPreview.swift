import AppKit
import BackupEngine
import QuickLookThumbnailing
import QuickLookUI
import SwiftUI

@MainActor
final class SavedOriginalThumbnails {
    static let shared = SavedOriginalThumbnails()
    private var active = 0

    func image(record: VerifiedBackupResource, folder: BackupDestinationStore) async throws -> CGImage {
        while active >= 4 { try await Task.sleep(for: .milliseconds(40)) }
        try Task.checkCancellation()
        active += 1
        defer { active -= 1 }
        let lease = try await folder.acquireLease(readOnly: true)
        defer { lease.release() }
        let url = try await SavedOriginalAccess.url(destination: lease.url, record: record)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 160, height: 160),
                                                   scale: 2, representationTypes: .thumbnail)
        // Await the physical callback even after cancellation, retaining security-scoped access.
        let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        try Task.checkCancellation()
        _ = try await SavedOriginalAccess.url(destination: lease.url, record: record)
        return representation.cgImage
    }
}

struct SavedOriginalThumbnail: View {
    let record: VerifiedBackupResource
    let folder: BackupDestinationStore
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else { Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary) }
        }
        .frame(width: 80, height: 70)
        .accessibilityHidden(true)
        .task(id: record.relativePath + record.sha256) {
            image = nil
            do {
                let result = try await SavedOriginalThumbnails.shared.image(record: record, folder: folder)
                try Task.checkCancellation()
                image = result
            } catch { /* A missing preview does not establish missing or damaged original bytes. */ }
        }
        .onDisappear { image = nil }
    }
}

struct SavedPreviewRequest: Identifiable {
    let id = UUID()
    let url: URL
    let lease: DestinationLease
}

struct SavedOriginalPreview: View {
    let request: SavedPreviewRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            SavedQuickLook(request: request)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

private struct SavedQuickLook: NSViewRepresentable {
    let request: SavedPreviewRequest

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = request.url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = request.url as NSURL }
    func makeCoordinator() -> SavedPreviewRequest { request }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: SavedPreviewRequest) { view.previewItem = nil }
}
