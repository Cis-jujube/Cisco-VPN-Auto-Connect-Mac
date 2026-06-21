import AppKit
import Foundation
import Vision

enum TOTPQRCodeReaderError: Error, LocalizedError {
    case imageNotReadable
    case qrCodeNotFound

    var errorDescription: String? {
        switch self {
        case .imageNotReadable:
            "Cannot read the selected image."
        case .qrCodeNotFound:
            "No QR code was found in the selected image."
        }
    }
}

enum TOTPQRCodeReader {
    static func firstPayload(in imageURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: imageURL) else {
            throw TOTPQRCodeReaderError.imageNotReadable
        }
        return try firstPayload(in: image)
    }

    static func firstPayload(in pasteboard: NSPasteboard = .general) throws -> String {
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            return try firstPayload(in: image)
        }

        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           url.isFileURL {
            return try firstPayload(in: url)
        }

        if let rawFileURL = pasteboard.string(forType: .fileURL),
           let url = URL(string: rawFileURL),
           url.isFileURL {
            return try firstPayload(in: url)
        }

        throw TOTPQRCodeReaderError.imageNotReadable
    }

    static func firstPayload(in image: NSImage) throws -> String {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw TOTPQRCodeReaderError.imageNotReadable
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        guard let payload = request.results?.compactMap(\.payloadStringValue).first else {
            throw TOTPQRCodeReaderError.qrCodeNotFound
        }

        return payload
    }
}
