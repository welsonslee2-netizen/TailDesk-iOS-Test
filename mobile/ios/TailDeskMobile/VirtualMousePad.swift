import SwiftUI

struct VirtualMousePad: View {
    @ObservedObject var client: RemoteClient
    @Binding var dragLocked: Bool
    @State private var previousTranslation = CGSize.zero

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    HStack(spacing: 8) {
                        Image(systemName: "cursorarrow.motionlines")
                        Text(dragLocked ? "拖动锁定中" : "滑动移动 · 轻点单击")
                            .font(.caption)
                    }
                    .foregroundStyle(dragLocked ? Color.orange : Color.secondary)
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
                .frame(minHeight: 62)

                HStack(spacing: 1) {
                    mouseButton("左键", system: "computermouse", prominent: true) { client.clickCurrent() }
                    mouseButton("右键", system: "contextualmenu.and.cursorarrow") { client.clickCurrent(right: true) }
                }
                .frame(height: 38)
            }

            VStack(spacing: 6) {
                mouseButton(dragLocked ? "松开" : "拖动", system: dragLocked ? "lock.open" : "hand.draw") {
                    dragLocked.toggle()
                    client.leftButton(down: dragLocked)
                }
                HStack(spacing: 5) {
                    squareButton("chevron.up") { client.scroll(120) }
                    squareButton("chevron.down") { client.scroll(-120) }
                }
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func mouseButton(_ title: String, system: String, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.caption2.weight(.medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? .accentColor : .gray)
    }

    private func squareButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
