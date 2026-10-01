import AppKit
import RawViewerCore
import SwiftUI

/// 點一下：瀏覽模式切到該張；比對模式設為 A，⌥＋點一下設為 B。右鍵選單也可以設定 A／B。
struct ThumbnailStrip: View {
    let model: ViewerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                        ThumbnailCell(model: model, index: index, photo: photo)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 112)
            .background(.bar)
            .onChange(of: model.current) { _, index in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }
}

private struct ThumbnailCell: View {
    let model: ViewerModel
    let index: Int
    let photo: PhotoFile

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image = model.store.thumbnail(for: photo.url) {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 120, height: 80)

                HStack(spacing: 2) {
                    if model.aIndex == index { tag("A", .orange) }
                    if model.bIndex == index { tag("B", .cyan) }
                }
                .padding(3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(borderColor, lineWidth: isHighlighted ? 3 : 0)
            )
            Text(photo.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 120)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.mode == .compare {
                NSEvent.modifierFlags.contains(.option) ? model.setB(index) : model.setA(index)
            } else {
                model.select(index)
            }
        }
        .contextMenu {
            Button("設為 A") { model.setA(index) }
            Button("設為 B") { model.setB(index) }
        }
        .onAppear { model.store.requestThumbnail(photo.url) }
    }

    private var isHighlighted: Bool {
        model.mode == .compare ? (model.aIndex == index || model.bIndex == index) : model.current == index
    }

    private var borderColor: Color {
        guard model.mode == .compare else { return .accentColor }
        return model.aIndex == index ? .orange : .cyan
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.black)
    }
}
