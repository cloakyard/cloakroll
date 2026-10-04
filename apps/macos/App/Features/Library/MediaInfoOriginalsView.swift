import MediaModels
import SwiftUI
import UniformTypeIdentifiers

struct MediaInfoOriginalsView: View {
    let resources: [MediaResource]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Original Files").font(.headline)
                Spacer()
                Text(resources.count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(resources.count) original \(resources.count == 1 ? "file" : "files")")
            }
            if resources.isEmpty {
                Text("Original file details aren’t available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                GroupBox {
                    LazyVStack(spacing: 0) {
                        ForEach(resources) { resource in
                            if resource.id != resources.first?.id { Divider().padding(.vertical, 10) }
                            resourceRow(resource)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private func resourceRow(_ resource: MediaResource) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: resource))
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(resource.filename)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Format.bytes(resource.byteCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(resource.filename), \(Format.bytes(resource.byteCount))")
    }

    private func symbol(for resource: MediaResource) -> String {
        let fileExtension = (resource.filename as NSString).pathExtension
        guard let type = UTType(filenameExtension: fileExtension) else { return "doc" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .image) { return "photo" }
        return "doc"
    }
}
