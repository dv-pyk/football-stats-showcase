import UIKit

extension UIImage {
    func opaqueForClipboard() -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = scale

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
