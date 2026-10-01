import Foundation
import XCTest

@testable import RawViewerCore

final class PhotoScannerTests: XCTestCase {
    func testScanFiltersAndSortsNaturally() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["DSC10.ARW", "DSC9.arw", "DSC1.ARW", "._DSC1.ARW", "notes.txt", "DSC2.JPG"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }

        let names = try PhotoScanner.scan(folder: dir).map(\.name)

        XCTAssertEqual(names, ["DSC1.ARW", "DSC9.arw", "DSC10.ARW"])
    }
}

final class LRUCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        cache.touch("a")
        cache.insert(3, for: "c")

        XCTAssertEqual(cache.peek("a"), 1)
        XCTAssertNil(cache.peek("b"))
        XCTAssertEqual(cache.peek("c"), 3)
        XCTAssertEqual(cache.count, 2)
    }

    func testReinsertDoesNotDuplicate() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "a")
        cache.insert(3, for: "b")

        XCTAssertEqual(cache.peek("a"), 2)
        XCTAssertEqual(cache.count, 2)
    }
}

final class MetadataFormattingTests: XCTestCase {
    func testExposureFormatting() {
        XCTAssertEqual(PhotoMetadata.formatExposure(1.0 / 250), "1/250s")
        XCTAssertEqual(PhotoMetadata.formatExposure(0.003125), "1/320s")
        XCTAssertEqual(PhotoMetadata.formatExposure(2), "2s")
        XCTAssertEqual(PhotoMetadata.formatExposure(0.5), "0.5s")
    }

    func testSummary() {
        let meta = PhotoMetadata(exposureTime: 1.0 / 125, fNumber: 2.8, iso: 400, focalLength: 35)
        XCTAssertEqual(meta.exposureSummary, "1/125s · f/2.8 · ISO 400 · 35mm")
    }
}

final class ARWReaderTests: XCTestCase {
    func testRejectsNonTIFFAndTruncatedFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let garbage = dir.appendingPathComponent("garbage.ARW")
        try Data("not a raw file".utf8).write(to: garbage)
        XCTAssertThrowsError(try ARWReader(url: garbage))

        // TIFF 標頭正確，但 IFD 位移指到檔案外面
        let truncated = dir.appendingPathComponent("truncated.ARW")
        try Data([0x49, 0x49, 0x2A, 0x00, 0xFF, 0xFF, 0x00, 0x00]).write(to: truncated)
        XCTAssertThrowsError(try ARWReader(url: truncated))
        XCTAssertNil(ImageLoader.preview(url: truncated))
    }

    func testReadsMinimalTIFF() throws {
        // IFD0：Model = "ILCE-7M3"、Orientation = 6；沒有 JPEG
        var bytes: [UInt8] = [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]
        bytes += [0x02, 0x00]  // 2 entries
        bytes += [0x10, 0x01, 0x02, 0x00, 0x09, 0x00, 0x00, 0x00, 0x26, 0x00, 0x00, 0x00]  // Model -> offset 38
        bytes += [0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00]  // Orientation
        bytes += [0x00, 0x00, 0x00, 0x00]  // next IFD
        bytes += Array("ILCE-7M3\0".utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ARW")
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let arw = try ARWReader(url: url)

        XCTAssertEqual(arw.metadata.cameraModel, "ILCE-7M3")
        XCTAssertEqual(arw.orientation, 6)
        XCTAssertNil(arw.previewJPEG)
    }
}

/// 需要真實 ARW 樣本：`RAW_VIEWER_SAMPLES=/path/to/arw swift test`
/// 樣本不放進 repo，可從 https://raw.pixls.us/data/Sony/ 下載。
final class SampleImageTests: XCTestCase {
    func testLoadsSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["RAW_VIEWER_SAMPLES"] else {
            throw XCTSkip("RAW_VIEWER_SAMPLES not set")
        }
        let photos = try PhotoScanner.scan(folder: URL(fileURLWithPath: dir))
        XCTAssertFalse(photos.isEmpty)

        for photo in photos {
            var start = Date()
            let preview = try XCTUnwrap(ImageLoader.preview(url: photo.url), photo.name)
            let previewTime = Date().timeIntervalSince(start)
            XCTAssertLessThan(previewTime, 0.5, "預覽應該不經過 RAW 外掛，\(photo.name)")
            XCTAssertNotNil(ImageLoader.thumbnail(url: photo.url))
            let meta = ImageLoader.metadata(url: photo.url)
            let imageIOMeta = ImageLoader.imageIOMetadata(url: photo.url)
            XCTAssertEqual(meta.cameraModel, imageIOMeta.cameraModel, photo.name)
            XCTAssertEqual(meta.exposureTime, imageIOMeta.exposureTime, photo.name)
            XCTAssertEqual(meta.fNumber, imageIOMeta.fNumber, photo.name)
            XCTAssertEqual(meta.iso, imageIOMeta.iso, photo.name)
            XCTAssertEqual(meta.focalLength, imageIOMeta.focalLength, photo.name)
            XCTAssertEqual(meta.captureDate, imageIOMeta.captureDate, photo.name)

            start = Date()
            let full = try XCTUnwrap(ImageLoader.fullResolution(url: photo.url), photo.name)
            let fullTime = Date().timeIntervalSince(start)

            print(String(
                format: "%@ [%@] preview %dx%d %.0fms | full %dx%d %.0fms | %@",
                photo.name, meta.cameraModel ?? "?", preview.width, preview.height, previewTime * 1000,
                full.width, full.height, fullTime * 1000, meta.exposureSummary))
            XCTAssertGreaterThanOrEqual(full.width * full.height, preview.width * preview.height)
        }
    }
}
