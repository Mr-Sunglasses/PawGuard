import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct ImportedCatPhoto {
    let avatarPath: String
    let previewPath: String
}

final class CatPhotoManager {
    let rootDirectory: URL
    private let imageContext = CIContext()

    init(fileManager: FileManager = .default) {
        let applicationSupport =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        rootDirectory = applicationSupport.appendingPathComponent("PawGuard/Cats", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func importPhotos(from urls: [URL], for profileID: UUID) -> [ImportedCatPhoto] {
        let directory = rootDirectory.appendingPathComponent(profileID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return urls.compactMap { url in
            guard let image = NSImage(contentsOf: url) else { return nil }
            let identifier = UUID().uuidString
            let avatarURL = directory.appendingPathComponent("photo-\(identifier)-avatar.jpg")
            let previewURL = directory.appendingPathComponent("photo-\(identifier)-preview.jpg")
            guard writeJPEG(image: image, to: avatarURL, maxDimension: 256, squareCrop: true),
                writeJPEG(image: image, to: previewURL, maxDimension: 1024, squareCrop: false)
            else {
                return nil
            }
            return ImportedCatPhoto(avatarPath: avatarURL.path, previewPath: previewURL.path)
        }
    }

    func deletePhoto(atPath path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        let previewPath = path.replacingOccurrences(of: "-avatar.jpg", with: "-preview.jpg")
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: previewPath))
    }

    func deletePhotos(for profileID: UUID) {
        let directory = rootDirectory.appendingPathComponent(profileID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeJPEG(image: NSImage, to url: URL, maxDimension: CGFloat, squareCrop: Bool) -> Bool {
        guard let cgImage = normalizedCGImage(from: image) else { return false }
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let cropSize = squareCrop ? min(sourceWidth, sourceHeight) : max(sourceWidth, sourceHeight)
        let cropRect =
            squareCrop
            ? CGRect(x: (sourceWidth - cropSize) / 2, y: (sourceHeight - cropSize) / 2, width: cropSize, height: cropSize)
            : CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return false }

        let scale = min(1, maxDimension / CGFloat(max(cropped.width, cropped.height)))
        let size = CGSize(width: max(1, CGFloat(cropped.width) * scale), height: max(1, CGFloat(cropped.height) * scale))
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cropped, size: size).draw(in: CGRect(origin: .zero, size: size))
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
        else {
            return false
        }
        do {
            try jpeg.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func normalizedCGImage(from image: NSImage) -> CGImage? {
        guard let tiff = image.tiffRepresentation,
            let source = CGImageSourceCreateWithData(tiff as CFData, nil),
            let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            var proposedRect = CGRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        let orientedImage = CIImage(cgImage: sourceImage).oriented(orientation)
        return imageContext.createCGImage(orientedImage, from: orientedImage.extent)
    }
}
