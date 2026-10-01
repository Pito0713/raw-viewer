import AppKit
import RawViewerCore
import SwiftUI

/// 顯示單張（瀏覽）或 A 半透明疊在 B 上（比對）。每張各自「符合視窗」後再套用共同的縮放和平移。
struct ImageCanvas: View {
    let model: ViewerModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                ZStack {
                    if model.mode == .compare {
                        layer(model.photoB, size: geo.size)
                        layer(model.photoA, size: geo.size)
                            .offset(model.aOffset)
                            .opacity(model.opacity)
                    } else {
                        layer(model.currentPhoto, size: geo.size)
                    }
                }
                .scaleEffect(model.zoom)
                .offset(model.pan)

                InteractionLayer(
                    onPan: model.panBy,
                    onMoveA: model.moveABy,
                    onZoom: model.zoom(by:anchor:),
                    onDoubleClick: model.resetView
                )

                overlayInfo
            }
            .clipped()
            .onAppear { model.canvasSize = geo.size }
            .onChange(of: geo.size) { _, size in model.canvasSize = size }
        }
    }

    @ViewBuilder
    private func layer(_ photo: PhotoFile?, size: CGSize) -> some View {
        if let photo, let image = model.store.bestImage(for: photo.url) {
            Image(decorative: image, scale: 1)
                .resizable()
                // 放大到看得到像素時改用最近鄰，方便檢查對焦。
                .interpolation(model.zoom > 6 ? .none : .high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        } else if photo != nil {
            ProgressView().controlSize(.large)
        }
    }

    private var overlayInfo: some View {
        VStack {
            HStack(alignment: .top) {
                if model.mode == .compare {
                    InfoBadge(label: "A", photo: model.photoA, model: model)
                    Spacer()
                    InfoBadge(label: "B", photo: model.photoB, model: model)
                } else {
                    InfoBadge(label: nil, photo: model.currentPhoto, model: model)
                    Spacer()
                    Text("\(model.current + 1) / \(model.photos.count)")
                        .modifier(BadgeStyle())
                }
            }
            Spacer()
            HStack {
                Spacer()
                Text(model.zoom == 1 ? "符合視窗" : String(format: "×%.1f", model.zoom))
                    .modifier(BadgeStyle())
            }
        }
        .padding(10)
        .allowsHitTesting(false)
    }
}

private struct InfoBadge: View {
    let label: String?
    let photo: PhotoFile?
    let model: ViewerModel

    var body: some View {
        if let photo {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let label { Text(label).bold().foregroundStyle(label == "A" ? .orange : .cyan) }
                    Text(photo.name).bold().lineLimit(1).truncationMode(.middle)
                    if !model.store.hasFullResolution(photo.url) {
                        Text("預覽").foregroundStyle(.secondary)
                    }
                }
                if let meta = model.store.metadata(for: photo.url) {
                    Text(meta.exposureSummary).foregroundStyle(.secondary)
                }
            }
            .modifier(BadgeStyle())
        }
    }
}

private struct BadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
    }
}

/// 用 AppKit 接滑鼠：拖曳平移、Shift＋拖曳移動 A、滾輪／觸控板縮放、雙擊回到符合視窗。
struct InteractionLayer: NSViewRepresentable {
    var onPan: (CGSize) -> Void
    var onMoveA: (CGSize) -> Void
    var onZoom: (CGFloat, CGPoint) -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        InteractionNSView()
    }

    func updateNSView(_ view: InteractionNSView, context: Context) {
        view.onPan = onPan
        view.onMoveA = onMoveA
        view.onZoom = onZoom
        view.onDoubleClick = onDoubleClick
    }
}

final class InteractionNSView: NSView {
    var onPan: (CGSize) -> Void = { _ in }
    var onMoveA: (CGSize) -> Void = { _ in }
    var onZoom: (CGFloat, CGPoint) -> Void = { _, _ in }
    var onDoubleClick: () -> Void = {}

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    /// 相對於畫布中心的座標（y 向下），與 SwiftUI offset 一致。
    private func anchor(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick() }
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = CGSize(width: event.deltaX, height: event.deltaY)
        event.modifierFlags.contains(.shift) ? onMoveA(delta) : onPan(delta)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // 觸控板雙指滑動 = 平移（按住 Shift 移動 A）
            let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
            event.modifierFlags.contains(.shift) ? onMoveA(delta) : onPan(delta)
        } else {
            // 滑鼠滾輪（或 ⌘＋觸控板）= 縮放
            let amount = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 50 : event.scrollingDeltaY
            onZoom(pow(1.15, amount), anchor(for: event))
        }
    }

    override func magnify(with event: NSEvent) {
        onZoom(1 + event.magnification, anchor(for: event))
    }
}
