import SwiftUI

struct VirtualMousePad: View {
    @ObservedObject var client: RemoteClient
    @Binding var dragLocked: Bool
    @State private var previousTranslation = CGSize.zero

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { _ in
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    VStack(spacing: 5) {
                        Image(systemName: "cursorarrow.motionlines")
                            .font(.title2)
                        Text("虚拟鼠标 · 滑动移动 · 轻点左键")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.75)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dx = value.translation.width - previousTranslation.width
                            let dy = value.translation.height - previousTranslation.height
                            previousTranslation = value.translation
                            if dx != 0 || dy != 0 { client.movePointer(dx: dx, dy: dy) }
                        }
                        .onEnded { value in
                            if abs(value.translation.width) < 5, abs(value.translation.height) < 5 {
                                client.clickCurrent()
                            }
                            previousTranslation = .zero
                        }
                )
                .accessibilityLabel("虚拟鼠标触控板")
            }
            .frame(minWidth: 170, minHeight: 86)

            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    compactButton("左键") { client.clickCurrent() }
                    compactButton("右键") { client.clickCurrent(right: true) }
                }
                HStack(spacing: 7) {
                    compactButton(dragLocked ? "松开" : "拖动") {
                        dragLocked.toggle()
                        client.leftButton(down: dragLocked)
                    }
                    compactButton("滚动") { client.scroll(-120) }
                }
            }
        }
        .padding(8)
    }

    private func compactButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .font(.caption)
            .frame(minWidth: 48, minHeight: 34)
    }
}
