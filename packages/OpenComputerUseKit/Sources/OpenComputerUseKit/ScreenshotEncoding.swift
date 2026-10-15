import AppKit
import CoreGraphics
import Foundation

/// Default ceiling on an encoded screenshot. Encodes above it are shrunk step by step, because a very large
/// image block makes some MCP hosts drop the whole tool result.
let screenshotResultMaxBytes = 900_000
/// The byte-ceiling shrink never goes below this fraction of the captured size.
let screenshotResultMinScale: CGFloat = 0.25

struct ScreenshotEncodingResult {
    let data: Data?
    /// Why `data` is nil, written for the model that reads the tool result.
    let note: String?
}

/// Encodes a captured window image according to `config`.
///
/// The long edge is capped first (or the screenshot is omitted when `scaleDownAfterMaxSize` is off), then the
/// result is re-encoded at smaller scales until it fits `maxBytes`. The caller maps coordinates against the pixel
/// size of the returned data, so every resize here stays consistent with click and drag input.
func encodeScreenshot(
    for image: CGImage,
    config: ImageCaptureConfig,
    maxBytes: Int = screenshotResultMaxBytes,
    minScale: CGFloat = screenshotResultMinScale
) -> ScreenshotEncodingResult {
    func omitted(_ reason: String) -> ScreenshotEncodingResult {
        ScreenshotEncodingResult(data: nil, note: "Screenshot omitted: " + reason)
    }
    guard image.width > 0, image.height > 0, maxBytes > 0 else { return omitted("invalid dimensions") }
    guard config.maxDimension.map({ $0.isFinite && $0 >= 1 && $0.rounded(.down) == $0 }) ?? true else {
        return omitted("invalid image configuration")
    }

    func isTiny(_ width: Int, _ height: Int) -> Bool {
        Double(width) * Double(height) < Double(config.discardBelowPixelCount)
    }
    if isTiny(image.width, image.height) {
        return omitted("\(image.width)×\(image.height) has fewer than \(config.discardBelowPixelCount) pixels")
    }

    let longEdge = CGFloat(max(image.width, image.height))
    if let maximum = config.maxDimension, longEdge > maximum, !config.scaleDownAfterMaxSize {
        return omitted("long edge \(renderedInt(longEdge)) exceeds maxLongEdgePixels \(renderedInt(maximum)); scaleDownAfterMaxSize is false")
    }

    func encode(_ image: CGImage) -> Data? {
        switch config.format {
        case .png:
            return pngData(for: image)
        case .jpg:
            return jpegData(for: image, quality: config.jpegQuality)
        }
    }

    var scale = min(1, (config.maxDimension ?? longEdge) / longEdge)
    var best: Data?
    while true {
        let size = scaledPixelSize(of: image, scale: scale)
        if isTiny(size.width, size.height) {
            if best == nil { return omitted("resizing would fall below discardBelowPixelCount \(config.discardBelowPixelCount)") }
            break
        }
        guard let candidate = scale == 1 ? image : resizedCGImage(image, scale: scale),
              let data = encode(candidate)
        else {
            if best == nil { return omitted("\(config.format.rawValue) encoding failed") }
            break
        }
        best = data
        if data.count <= maxBytes { break }
        scale *= 0.85
        if scale < minScale { break }
    }
    return ScreenshotEncodingResult(data: best, note: nil)
}

/// Fails an x/y input when the image settings left the screenshot out. There is no image to read the point from,
/// and an earlier image would be the wrong frame of reference.
func rejectCoordinateInputWhenScreenshotOmitted(_ snapshot: AppSnapshot) throws {
    if snapshot.screenshotData == nil, let note = snapshot.screenshotNote {
        throw ComputerUseError.stateUnavailable(note + "; coordinate input requires a delivered screenshot")
    }
}

private func pngData(for image: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])
}

private func jpegData(for image: CGImage, quality: Double) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
}

private func scaledPixelSize(of image: CGImage, scale: CGFloat) -> (width: Int, height: Int) {
    (
        max(1, renderedInt((CGFloat(image.width) * scale).rounded())),
        max(1, renderedInt((CGFloat(image.height) * scale).rounded()))
    )
}

private func resizedCGImage(_ image: CGImage, scale: CGFloat) -> CGImage? {
    let (width, height) = scaledPixelSize(of: image, scale: scale)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
