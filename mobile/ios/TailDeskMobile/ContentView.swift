import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var client: RemoteClient
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastEndpoint") private var endpoint = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var mode: ControlMode = .pad
    @State private var zoom: CGFloat = 1
    @State private var screenCommand = 0
    @State private var keyboardToken = 0
    @State private var dragLocked = false
    @State private var quality = -1

    var body: some View {
        Group {
            if client.connected { remoteView } else { loginView }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            if phase != .active { client.release(); dragLocked = false }
        }
    }

    private var loginView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("TailDesk").font(.largeTitle.bold())
                Text("通过 Tailscale 连接自己的电脑").foregroundStyle(.secondary)
                TextField("电脑地址，例如 100.101.102.103:59011", text: $endpoint)
                    .textInputAutocapitalization(.never).keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                SecureField("无人值守密码", text: $password).textFieldStyle(.roundedBorder)
                Button {
                    connecting = true
                    Task { await client.connect(endpoint: endpoint, password: password); connecting = false; if client.connected { password = "" } }
                } label: {
                    HStack { if connecting { ProgressView() }; Text(connecting ? "正在连接" : "连接电脑").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(connecting || endpoint.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                Text(client.status).font(.footnote).foregroundStyle(client.status.contains("失败") ? .red : .secondary)
                Spacer()
                Text("电脑端需开启“无人值守 / 手机控制”。App 仅接受 Tailscale IPv4，默认手机端口为电脑控制端口 + 1。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("远程控制")
        }
    }

    private var remoteView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.computer).font(.headline).lineLimit(1)
                    Text(client.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("控制方式", selection: $mode) {
                    ForEach(ControlMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                Button("断开") { client.disconnect() }.buttonStyle(.bordered)
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(.thinMaterial)

            ZStack(alignment: .bottomTrailing) {
                RemoteScreenView(client: client, mode: $mode, zoom: $zoom, command: screenCommand)
                    .clipped()
                RemoteKeyboard(client: client, focusToken: keyboardToken)
                    .frame(width: 2, height: 2).opacity(0.02)
                VStack(spacing: 6) {
                    mouseButton("左键") { client.clickCurrent() }
                    mouseButton("右键") { client.clickCurrent(right: true) }
                    mouseButton(dragLocked ? "松开" : "拖动") {
                        dragLocked.toggle(); client.leftButton(down: dragLocked)
                    }
                }
                .padding(8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(10)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toolButton("键盘", system: "keyboard") { keyboardToken += 1 }
                    toolButton("−", system: nil) { zoom = max(0.25, zoom / 1.25) }
                    Text("\(Int(zoom * 100))%").font(.caption.monospacedDigit()).frame(minWidth: 44)
                    toolButton("＋", system: nil) { zoom = min(8, zoom * 1.25) }
                    toolButton("适应", system: "arrow.up.left.and.arrow.down.right") { nextScreenCommand(fit: true) }
                    toolButton("原尺寸", system: "1.magnifyingglass") { nextScreenCommand(fit: false) }
                    toolButton("滚↑", system: nil) { client.scroll(120) }
                    toolButton("滚↓", system: nil) { client.scroll(-120) }
                    toolButton("退格", system: "delete.left") { client.key(8) }
                    toolButton("回车", system: "return") { client.key(13) }
                    Menu {
                        Button("自动画质") { setQuality(-1) }
                        Button("文字无损") { setQuality(0) }
                        Button("高清均衡") { setQuality(1) }
                        Button("流畅省流量") { setQuality(2) }
                    } label: { Label(qualityName, systemImage: "speedometer") }
                    .buttonStyle(.bordered)
                }
                .padding(8)
            }
            .background(.thinMaterial)
        }
    }

    private var qualityName: String {
        quality == 0 ? "文字" : quality == 1 ? "高清" : quality == 2 ? "流畅" : "自动"
    }

    private func setQuality(_ value: Int) { quality = value; client.quality(value) }

    private func nextScreenCommand(fit: Bool) {
        var next = screenCommand + 1
        if fit && next % 2 == 0 { next += 1 }
        if !fit && next % 2 == 1 { next += 1 }
        screenCommand = next
    }

    private func toolButton(_ title: String, system: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let system { Label(title, systemImage: system) } else { Text(title) }
        }.buttonStyle(.bordered)
    }

    private func mouseButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.borderedProminent).font(.caption).frame(minWidth: 52)
    }
}

#Preview { ContentView().environmentObject(RemoteClient()) }

