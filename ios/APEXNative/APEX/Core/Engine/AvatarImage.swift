import UIKit

/// Prepares a chosen photo for upload.
///
/// A picture straight from the camera roll is routinely 4 to 12 MB, and it is
/// about to be shown at 96 points across. Sending the original would cost the
/// user their data allowance to display something the size of a thumbnail, so
/// it is resized and compressed here, on the phone, before it goes anywhere.
enum AvatarImage {

    /// The longest edge of the stored image, in pixels.
    ///
    /// 512 covers the largest place an avatar appears on the biggest phone at
    /// 3x, with room to spare. Beyond that the file grows and nothing looks
    /// better.
    static let maximumEdge: CGFloat = 512

    /// Roughly the size of a small photo. Kept well under a megabyte so
    /// uploading works on a poor connection.
    static let targetBytes = 180_000

    /// Returns JPEG data ready to upload, or nil if the image cannot be drawn.
    static func prepare(_ image: UIImage) -> Data? {
        let square = cropToSquare(image)
        let scaled = resize(square, longestEdge: maximumEdge)

        /* Step the quality down until it fits, rather than picking one number
           and hoping. A flat photo reaches the target on the first try; a busy
           one takes a few passes and still looks right at this size. */
        for quality in stride(from: 0.85, through: 0.4, by: -0.15) {
            guard let data = scaled.jpegData(compressionQuality: quality) else { continue }
            if data.count <= targetBytes { return data }
        }
        return scaled.jpegData(compressionQuality: 0.4)
    }

    /// Avatars are shown in circles and squares, so a portrait photo is cropped
    /// to its centre here rather than being squashed by the view later.
    static func cropToSquare(_ image: UIImage) -> UIImage {
        let size = min(image.size.width, image.size.height)
        let origin = CGPoint(
            x: (image.size.width - size) / 2,
            y: (image.size.height - size) / 2
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { _ in
                image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
            }
    }

    static func resize(_ image: UIImage, longestEdge: CGFloat) -> UIImage {
        let pixelEdge = max(image.size.width, image.size.height) * image.scale
        guard pixelEdge > longestEdge else { return image }
        let ratio = longestEdge / pixelEdge
        let target = CGSize(width: image.size.width * image.scale * ratio,
                            height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
