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
    @State private var showMousePad = true
    @FocusState private var loginField: LoginField?

    private enum LoginField: Hashable { case endpoint, password }

    var body: some View {
        Group {
            if client.connected { remoteView } else { loginView }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.xSmall ... .accessibility1)
        .onChange(of: scenePhase) { phase in
            if phase != .active { client.release(); dragLocked = false }
        }
    }

    private var loginView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer(minLength: 24)
                    Text("TailDesk")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.75)
                    Text("通过 Tailscale 安全连接自己的电脑")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("电脑地址", systemImage: "desktopcomputer")
                            .font(.headline)
                        TextField("例如 100.119.102.126:59011", text: $endpoint)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.numbersAndPunctuation)
                            .textContentType(.URL)
                            .submitLabel(.next)
                            .focused($loginField, equals: .endpoint)
                            .onSubmit { loginField = .password }
                            .textFieldStyle(.roundedBorder)
                            .id(LoginField.endpoint)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("无人值守密码", systemImage: "lock")
                            .font(.headline)
                        SecureField("电脑端设置的 12–128 位密码", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($loginField, equals: .password)
                            .onSubmit { beginConnection() }
                            .textFieldStyle(.roundedBorder)
                            .id(LoginField.password)
                    }

                    Button(action: beginConnection) {
                        HStack {
                            if connecting { ProgressView() }
                            Text(connecting ? "正在验证并连接" : "连接电脑")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(connecting || endpoint.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: statusIcon)
                        Text(client.status)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .font(.footnote)
                    .foregroundStyle(statusColor)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                    Text("确保 iPhone 与电脑都已连接同一 Tailnet；手机端口通常是电脑端口 + 1。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: loginField) { field in
                guard let field else { return }
                withAnimation { proxy.scrollTo(field, anchor: .center) }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { loginField = nil }
                }
            }
        }
    }

    private var statusIcon: String {
        connecting ? "arrow.triangle.2.circlepath" : client.status == "尚未连接" ? "info.circle" : "exclamationmark.circle"
    }

    private var statusColor: Color {
        if connecting || client.status == "尚未连接" || client.status == "已断开" { return .gray }
        return .orange
    }

    private func beginConnection() {
        guard !connecting else { return }
        loginField = nil
        connecting = true
        Task {
            await client.connect(endpoint: endpoint, password: password)
            connecting = false
            if client.connected { password = "" }
        }
    }

    private var remoteView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.computer).font(.headline).lineLimit(1)
                    Text(client.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Menu {
                    Picker("控制方式", selection: $mode) {
                        ForEach(ControlMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button(showMousePad ? "隐藏虚拟鼠标" : "显示虚拟鼠标") { showMousePad.toggle() }
                } label: {
                    Label("控制", systemImage: "cursorarrow.motionlines")
                }
                .buttonStyle(.bordered)
                Button("断开") { client.disconnect() }.buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.thinMaterial)

            ZStack(alignment: .topTrailing) {
                RemoteScreenView(client: client, mode: $mode, zoom: $zoom, command: screenCommand)
                    .clipped()
                RemoteKeyboard(client: client, focusToken: keyboardToken)
                    .frame(width: 2, height: 2)
                    .opacity(0.01)
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
            .frame(maxHeight: .infinity)

            if showMousePad {
                VirtualMousePad(client: client, dragLocked: $dragLocked)
                    .frame(height: 112)
                    .background(.thinMaterial)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toolButton("键盘", system: "keyboard") { keyboardToken += 1 }
                    toolButton("鼠标", system: "cursorarrow") { showMousePad.toggle() }
                    toolButton("−", system: nil) { zoom = max(0.25, zoom / 1.25) }
                    toolButton("＋", system: nil) { zoom = min(8, zoom * 1.25) }
                    toolButton("适应", system: "arrow.up.left.and.arrow.down.right") { nextScreenCommand(fit: true) }
                    toolButton("原尺寸", system: "1.magnifyingglass") { nextScreenCommand(fit: false) }
                    toolButton("滚↑", system: nil) { client.scroll(120) }
                    toolButton("滚↓", system: nil) { client.scroll(-120) }
                    toolButton("退格", system: "delete.left") { client.key(8) }
                    toolButton("回车", system: "return") { client.key(13) }
                    Menu {
                        Button("自动画质") { setQuality(-1) }
                        Button("文字清晰") { setQuality(0) }
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
        }
        .buttonStyle(.bordered)
    }
}

#Preview { ContentView().environmentObject(RemoteClient()) }
