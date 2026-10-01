import CoreGraphics
import Foundation
import Observation
import RawViewerCore

/// 三層快取：縮圖、內嵌預覽、完整解析度。載入在背景執行，完成後觸發畫面更新。
@MainActor
@Observable
final class ImageStore {
    private enum Kind: String {
        case thumbnail, preview, full
    }

    private var thumbnails = LRUCache<URL, CGImage>(capacity: 600)
    private var previews = LRUCache<URL, CGImage>(capacity: 30)
    // 完整解析度每張約 100MB，只留畫面上正在用的幾張。
    private var fulls = LRUCache<URL, CGImage>(capacity: 4)
    private var metadata: [URL: PhotoMetadata] = [:]
    @ObservationIgnored private var inflight: Set<String> = []

    func bestImage(for url: URL) -> CGImage? {
        fulls.peek(url) ?? previews.peek(url)
    }

    func hasFullResolution(_ url: URL) -> Bool {
        fulls.peek(url) != nil
    }

    func thumbnail(for url: URL) -> CGImage? {
        thumbnails.peek(url)
    }

    func metadata(for url: URL) -> PhotoMetadata? {
        metadata[url]
    }

    func reset() {
        thumbnails.removeAll()
        previews.removeAll()
        fulls.removeAll()
        metadata.removeAll()
    }

    func requestThumbnail(_ url: URL) {
        guard thumbnails.peek(url) == nil else { return }
        load(.thumbnail, url, priority: .utility) { ImageLoader.thumbnail(url: url) }
    }

    func requestPreview(_ url: URL) {
        if metadata[url] == nil {
            load(.preview, url, priority: .userInitiated) { ImageLoader.preview(url: url) } onMetadata: {
                ImageLoader.metadata(url: url)
            }
        } else if previews.peek(url) == nil {
            load(.preview, url, priority: .userInitiated) { ImageLoader.preview(url: url) }
        } else {
            previews.touch(url)
        }
    }

    func requestFull(_ url: URL) {
        guard fulls.peek(url) == nil else {
            fulls.touch(url)
            return
        }
        load(.full, url, priority: .userInitiated) { ImageLoader.fullResolution(url: url) }
    }

    private func load(
        _ kind: Kind, _ url: URL, priority: TaskPriority,
        work: @escaping @Sendable () -> CGImage?,
        onMetadata: (@Sendable () -> PhotoMetadata)? = nil
    ) {
        let key = kind.rawValue + "|" + url.path
        guard !inflight.contains(key) else { return }
        inflight.insert(key)
        Task.detached(priority: priority) {
            let meta = onMetadata?()
            let image = work()
            await MainActor.run {
                self.inflight.remove(key)
                if let meta { self.metadata[url] = meta }
                guard let image else { return }
                switch kind {
                case .thumbnail: self.thumbnails.insert(image, for: url)
                case .preview: self.previews.insert(image, for: url)
                case .full: self.fulls.insert(image, for: url)
                }
            }
        }
    }
}
