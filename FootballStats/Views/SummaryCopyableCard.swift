import SwiftUI
import UIKit

struct SummaryCopyableCard<Content: View>: View {
    let title: String
    let copyText: String
    let cardWidth: CGFloat
    var customImage: (() -> UIImage?)?
    @ViewBuilder let content: Content

    @State private var copiedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                copyButtons
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .top) {
            if let copiedMessage {
                Text(copiedMessage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
    }

    private var copyButtons: some View {
        HStack(spacing: 2) {
            Button(action: copyTextToClipboard) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Copy text")

            Button(action: copyImageToClipboard) {
                Image(systemName: "photo.on.rectangle.angled")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Copy image")
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func copyTextToClipboard() {
        let fullText = copyText.isEmpty ? title : "\(title)\n\(copyText)"
        UIPasteboard.general.string = fullText
        flashCopied("Copied text")
    }

    private func copyImageToClipboard() {
        let image: UIImage?
        if let customImage {
            image = customImage()
        } else {
            image = renderedSnapshotImage()
        }
        guard let image, let opaque = image.opaqueForClipboard() else { return }
        UIPasteboard.general.image = opaque
        flashCopied("Copied image")
    }

    private func renderedSnapshotImage() -> UIImage? {
        let snapshot = VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(width: cardWidth, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))

        let renderer = ImageRenderer(content: snapshot)
        renderer.isOpaque = true
        renderer.scale = 3
        return renderer.uiImage
    }

    private func flashCopied(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedMessage = nil
            }
        }
    }
}
