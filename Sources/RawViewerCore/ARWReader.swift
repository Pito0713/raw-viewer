import Foundation

/// 直接從 Sony ARW（TIFF 結構）讀出內嵌 JPEG 和 EXIF，不經過 macOS 的 RAW 外掛。
///
/// 原因：macOS 的 RawCamera 外掛在每個程序第一次開某個機型時會卡約 5 秒（連 `sips` 也是），
/// 快速瀏覽無法接受。ARW 的結構：
/// - IFD0：預覽 JPEG（多數機型 1616×1080）、方向、機型、EXIF 指標、SubIFD（RAW 資料）
/// - IFD1：縮圖 JPEG（160×120，4:3 含黑邊）
public struct ARWReader {
    public let previewJPEG: Data?
    public let thumbnailJPEG: Data?
    /// TIFF/EXIF 方向（1 = 正常）。
    public let orientation: Int
    public let metadata: PhotoMetadata

    public init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard let tiff = TIFF(data: data), let ifd0 = tiff.ifd(at: tiff.firstIFDOffset) else {
            throw ARWError.notTIFF
        }
        previewJPEG = tiff.jpeg(in: ifd0)
        let ifd1 = ifd0.nextOffset.flatMap(tiff.ifd(at:))
        thumbnailJPEG = ifd1.flatMap(tiff.jpeg(in:))
        orientation = ifd0.entries[Tag.orientation].flatMap(tiff.integer) ?? 1

        let exif = ifd0.entries[Tag.exifIFD].flatMap(tiff.integer).flatMap(tiff.ifd(at:))
        let rawIFD = ifd0.entries[Tag.subIFDs].flatMap(tiff.integer).flatMap(tiff.ifd(at:))
        let size = rawIFD.flatMap { tiff.integers($0.entries[Tag.defaultCropSize]) }
            ?? rawIFD.map { [$0.entries[Tag.width].flatMap(tiff.integer), $0.entries[Tag.height].flatMap(tiff.integer)].compactMap { $0 } }
        metadata = PhotoMetadata(
            cameraModel: ifd0.entries[Tag.model].flatMap(tiff.string),
            exposureTime: exif?.entries[Tag.exposureTime].flatMap(tiff.rational),
            fNumber: exif?.entries[Tag.fNumber].flatMap(tiff.rational),
            iso: exif?.entries[Tag.iso].flatMap(tiff.integer),
            focalLength: exif?.entries[Tag.focalLength].flatMap(tiff.rational),
            captureDate: exif?.entries[Tag.dateTimeOriginal].flatMap(tiff.string),
            pixelWidth: size?.count == 2 ? size?[0] : nil,
            pixelHeight: size?.count == 2 ? size?[1] : nil
        )
    }
}

public enum ARWError: Error {
    case notTIFF
}

private enum Tag {
    static let width: UInt16 = 0x0100
    static let height: UInt16 = 0x0101
    static let model: UInt16 = 0x0110
    static let orientation: UInt16 = 0x0112
    static let subIFDs: UInt16 = 0x014A
    static let jpegOffset: UInt16 = 0x0201
    static let jpegLength: UInt16 = 0x0202
    static let exposureTime: UInt16 = 0x829A
    static let fNumber: UInt16 = 0x829D
    static let exifIFD: UInt16 = 0x8769
    static let iso: UInt16 = 0x8827
    static let dateTimeOriginal: UInt16 = 0x9003
    static let focalLength: UInt16 = 0x920A
    static let defaultCropSize: UInt16 = 0xC620
}

/// 最小的 TIFF 讀取器：只解析需要的欄位，所有讀取都做邊界檢查，壞檔回傳 nil 而不是當掉。
struct TIFF {
    struct Entry {
        let type: UInt16
        let count: UInt32
        /// 值本身（≤ 4 bytes 時）所在位置，或指向值的位移所在位置。
        let fieldOffset: Int
    }

    struct IFD {
        let entries: [UInt16: Entry]
        let nextOffset: Int?
    }

    let data: Data
    let littleEndian: Bool
    private(set) var firstIFDOffset = 0

    init?(data: Data) {
        self.data = data
        guard data.count >= 8 else { return nil }
        switch (data[data.startIndex], data[data.startIndex + 1]) {
        case (0x49, 0x49): littleEndian = true
        case (0x4D, 0x4D): littleEndian = false
        default: return nil
        }
        guard let magic = u16(2), magic == 42, let first = u32(4) else { return nil }
        firstIFDOffset = Int(first)
    }

    func ifd(at offset: Int) -> IFD? {
        guard offset > 0, let count = u16(offset) else { return nil }
        var entries: [UInt16: Entry] = [:]
        for i in 0..<Int(count) {
            let base = offset + 2 + i * 12
            guard let tag = u16(base), let type = u16(base + 2), let n = u32(base + 4) else { return nil }
            entries[tag] = Entry(type: type, count: n, fieldOffset: base + 8)
        }
        let next = u32(offset + 2 + Int(count) * 12).map(Int.init)
        return IFD(entries: entries, nextOffset: next == 0 ? nil : next)
    }

    func jpeg(in ifd: IFD) -> Data? {
        guard let start = ifd.entries[Tag.jpegOffset].flatMap(integer),
            let length = ifd.entries[Tag.jpegLength].flatMap(integer),
            length > 2, start >= 0, start + length <= data.count
        else { return nil }
        let jpeg = data.subdata(in: data.startIndex + start..<data.startIndex + start + length)
        // 只接受一般 JPEG（SOI 標記）；有些機型的 RAW 本身是無損 JPEG，不能當預覽用。
        return jpeg.starts(with: [0xFF, 0xD8]) ? jpeg : nil
    }

    /// SHORT 或 LONG 的第一個值。
    func integer(_ entry: Entry) -> Int? {
        integers(entry)?.first
    }

    func integers(_ entry: Entry?) -> [Int]? {
        guard let entry, entry.count > 0, entry.count <= 16 else { return nil }
        let size: Int
        switch entry.type {
        case 3: size = 2  // SHORT
        case 4, 13: size = 4  // LONG, IFD
        default: return nil
        }
        let total = size * Int(entry.count)
        guard let base = total <= 4 ? entry.fieldOffset : u32(entry.fieldOffset).map(Int.init) else { return nil }
        let values = (0..<Int(entry.count)).compactMap { i in
            size == 2 ? u16(base + i * 2).map(Int.init) : u32(base + i * 4).map(Int.init)
        }
        return values.count == Int(entry.count) ? values : nil
    }

    func rational(_ entry: Entry) -> Double? {
        guard entry.type == 5 || entry.type == 10, let offset = u32(entry.fieldOffset).map(Int.init),
            let numerator = u32(offset), let denominator = u32(offset + 4), denominator != 0
        else { return nil }
        if entry.type == 10 {
            return Double(Int32(bitPattern: numerator)) / Double(Int32(bitPattern: denominator))
        }
        return Double(numerator) / Double(denominator)
    }

    func string(_ entry: Entry) -> String? {
        guard entry.type == 2, entry.count > 0, entry.count < 4096 else { return nil }
        let length = Int(entry.count)
        guard let base = length <= 4 ? entry.fieldOffset : u32(entry.fieldOffset).map(Int.init),
            let bytes = bytes(base, length)
        else { return nil }
        let trimmed = bytes.prefix { $0 != 0 }
        let value = String(decoding: trimmed, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func bytes(_ offset: Int, _ length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= data.count else { return nil }
        return data.subdata(in: data.startIndex + offset..<data.startIndex + offset + length)
    }

    private func u16(_ offset: Int) -> UInt16? {
        guard let b = bytes(offset, 2) else { return nil }
        let value = UInt16(b[b.startIndex]) | UInt16(b[b.startIndex + 1]) << 8
        return littleEndian ? value : value.byteSwapped
    }

    private func u32(_ offset: Int) -> UInt32? {
        guard let b = bytes(offset, 4) else { return nil }
        let value = b.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        return littleEndian ? value : value.byteSwapped
    }
}
