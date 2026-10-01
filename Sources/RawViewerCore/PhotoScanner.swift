import Foundation

public struct PhotoFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL) {
        self.url = url
    }
}

public enum PhotoScanner {
    /// 目前只支援 Sony ARW。
    public static let supportedExtensions: Set<String> = ["arw"]

    /// 列出資料夾（不含子資料夾）內支援的 RAW 檔，依檔名自然排序。
    public static func scan(folder: URL) throws -> [PhotoFile] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter(isSupported)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(PhotoFile.init)
    }

    static func isSupported(_ url: URL) -> Bool {
        // 記憶卡在 exFAT 上常見 macOS 產生的 "._xxx.ARW" 中繼資料檔，不是照片。
        guard !url.lastPathComponent.hasPrefix("._") else { return false }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
