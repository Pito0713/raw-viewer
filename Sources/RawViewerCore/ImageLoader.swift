import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public struct PhotoMetadata: Equatable, Sendable {
    public var cameraModel: String?
    public var exposureTime: Double?
    public var fNumber: Double?
    public var iso: Int?
    public var focalLength: Double?
    public var captureDate: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(
        cameraModel: String? = nil, exposureTime: Double? = nil, fNumber: Double? = nil, iso: Int? = nil,
        focalLength: Double? = nil, captureDate: String? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil
    ) {
        self.cameraModel = cameraModel
        self.exposureTime = exposureTime
        self.fNumber = fNumber
        self.iso = iso
        self.focalLength = focalLength
        self.captureDate = captureDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// 例如 "1/250s · f/2.8 · ISO 400 · 35mm"
    public var exposureSummary: String {
        var parts: [String] = []
        if let exposureTime { parts.append(Self.formatExposure(exposureTime)) }
        if let fNumber { parts.append("f/" + Self.trim(fNumber)) }
        if let iso { parts.append("ISO \(iso)") }
        if let focalLength { parts.append(Self.trim(focalLength) + "mm") }
        return parts.joined(separator: " · ")
    }

    public static func formatExposure(_ seconds: Double) -> String {
        guard seconds > 0 else { return "-" }
        if seconds >= 0.3 { return trim(seconds) + "s" }
        return "1/\(Int((1 / seconds).rounded()))s"
    }

    static func trim(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// 讀取 RAW：預覽和縮圖直接取 ARW 內嵌 JPEG（毫秒級），完整解析度才交給 macOS ImageIO 解 RAW（秒級）。
/// 完整解碼支援的 Sony 機型以系統 RAW 支援清單為準。
public enum ImageLoader {
    /// 內嵌預覽 JPEG；讀不到時退回 ImageIO。
    public static func preview(url: URL, maxPixelSize: Int = 2560) -> CGImage? {
        if let arw = try? ARWReader(url: url), let jpeg = arw.previewJPEG,
            let image = decodeJPEG(jpeg, maxPixelSize: maxPixelSize, orientation: arw.orientation)
        {
            return image
        }
        return embeddedImage(url: url, maxPixelSize: maxPixelSize)
    }

    /// 縮圖列用的小圖。用預覽縮小而不用 ARW 內建的 160×120 縮圖——後者上下有黑邊。
    public static func thumbnail(url: URL, maxPixelSize: Int = 320) -> CGImage? {
        preview(url: url, maxPixelSize: maxPixelSize)
    }

    /// 完整解 RAW 並套用拍攝方向。
    public static func fullResolution(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func metadata(url: URL) -> PhotoMetadata {
        if let arw = try? ARWReader(url: url) { return arw.metadata }
        return imageIOMetadata(url: url)
    }

    static func imageIOMetadata(url: URL) -> PhotoMetadata {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return PhotoMetadata() }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        return PhotoMetadata(
            cameraModel: tiff[kCGImagePropertyTIFFModel] as? String,
            exposureTime: exif[kCGImagePropertyExifExposureTime] as? Double,
            fNumber: exif[kCGImagePropertyExifFNumber] as? Double,
            iso: (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first,
            focalLength: exif[kCGImagePropertyExifFocalLength] as? Double,
            captureDate: exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            pixelWidth: props[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: props[kCGImagePropertyPixelHeight] as? Int
        )
    }

    private static let ciContext = CIContext()

    private static func decodeJPEG(_ jpeg: Data, maxPixelSize: Int, orientation: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // 方向記在 ARW 的 TIFF 標籤，內嵌 JPEG 本身沒有，要自己轉。
        guard orientation != 1, let value = CGImagePropertyOrientation(rawValue: UInt32(orientation)) else { return image }
        let oriented = CIImage(cgImage: image).oriented(value)
        return ciContext.createCGImage(oriented, from: oriented.extent)
    }

    private static func embeddedImage(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
