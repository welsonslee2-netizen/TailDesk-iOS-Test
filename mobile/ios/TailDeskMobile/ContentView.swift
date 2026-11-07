import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var client: RemoteClient
    @EnvironmentObject private var history: ConnectionHistoryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastEndpoint") private var endpoint = ""
    @AppStorage("lastMacAddress") private var macAddress = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var mode: ControlMode = .pad
    @State private var zoom: CGFloat = 1
    @State private var screenCommand = 0
    @State private var keyboardToken = 0
    @State private var dragLocked = false
    @State private var quality = -1
    @State private var showMousePad = true
    @State private var isFullscreen = false
    @State private var showNetworkSetup = false
    @FocusState private var loginField: LoginField?

    private enum LoginField: Hashable { case endpoint, mac, password }

    var body: some View {
        Group {
            if client.connected { remoteView } else { loginView }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.xSmall ... .accessibility1)
        .statusBarHidden(isFullscreen && client.connected)
        .onChange(of: scenePhase) { phase in
            if phase != .active { client.release(); dragLocked = false }
        }
        .onChange(of: client.connected) { connected in
            if !connected, isFullscreen { leaveFullscreen() }
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
                    Text("局域网优先直连，外网支持 EasyTier 国内 P2P / Tailscale")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if !history.entries.isEmpty {
                        Menu {
                            ForEach(history.entries) { entry in
                                Button(entry.title) { selectHistory(entry) }
                            }
                            Divider()
                            Button("清空历史连接", role: .destructive) { history.removeAll() }
                        } label: {
                            Label("历史连接（\(history.entries.count)）", systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button { showNetworkSetup = true } label: {
                        Label("国内 P2P 配置", systemImage: "network")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("电脑地址", systemImage: "desktopcomputer")
                            .font(.headline)
                        TextField("例如 192.168.1.20:59011", text: $endpoint)
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
                        Label("网卡 MAC（用于局域网唤醒）", systemImage: "power")
                            .font(.headline)
                        TextField("例如 AA:BB:CC:DD:EE:FF", text: $macAddress)
                            .textInputAutocapitalization(.characters)
                            .keyboardType(.asciiCapable)
                            .submitLabel(.next)
                            .focused($loginField, equals: .mac)
                            .onSubmit { loginField = .password }
                            .textFieldStyle(.roundedBorder)
                            .id(LoginField.mac)
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
                            Text(connecting ? "正在唤醒并连接" : "连接电脑")
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

                    Text("点击“连接电脑”时会自动发送一次局域网唤醒包并等待电脑上线，无需反复点击。要求 iPhone 与电脑位于同一局域网，且电脑 BIOS/网卡已开启 Wake-on-LAN。")
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
            .sheet(isPresented: $showNetworkSetup) {
                NetworkSetupView(endpoint: $endpoint)
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
        let submittedPassword = password
        let submittedEndpoint = endpoint
        let submittedMac = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            var wakeSent = false
            if !submittedMac.isEmpty {
                do {
                    try WakeOnLAN.send(macAddress: submittedMac)
                    wakeSent = true
                    client.status = "已发送唤醒包，正在等待电脑和 Tailscale 上线…"
                } catch {
                    client.status = "唤醒包发送失败，继续尝试直接连接：\(error.localizedDescription)"
                }
            }
            let maximumAttempts = wakeSent ? 7 : 1
            for attempt in 1...maximumAttempts {
                if Task.isCancelled { break }
                if attempt > 1 {
                    client.status = "电脑正在启动，自动重试连接（\(attempt)/\(maximumAttempts)）…"
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                await client.connect(endpoint: submittedEndpoint, password: submittedPassword)
                if client.connected { break }
            }
            connecting = false
            if client.connected {
                let detectedMac = client.computerMac.trimmingCharacters(in: .whitespacesAndNewlines)
                if !detectedMac.isEmpty { macAddress = detectedMac }
                history.save(endpoint: submittedEndpoint, computer: client.computer, password: submittedPassword,
                             macAddress: detectedMac.isEmpty ? submittedMac : detectedMac)
                password = ""
            } else if wakeSent {
                client.status = "已发送唤醒包，但电脑尚未上线。请检查有线网卡、BIOS Wake-on-LAN 和局域网条件。"
            }
        }
    }

    private func selectHistory(_ entry: SavedConnection) {
        endpoint = entry.endpoint
        macAddress = entry.macAddress ?? ""
        password = history.password(for: entry)
        loginField = password.isEmpty ? .password : nil
    }

    private var remoteView: some View {
        VStack(spacing: 0) {
            if !isFullscreen {
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
                Button { enterFullscreen() } label: {
                    Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                Button("断开") { client.disconnect() }.buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.thinMaterial)
            }

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
                if isFullscreen {
                    HStack(spacing: 8) {
                        floatingButton("keyboard", label: "键盘") { keyboardToken += 1 }
                        floatingButton("cursorarrow.motionlines", label: "虚拟鼠标") { showMousePad.toggle() }
                        floatingButton("arrow.down.right.and.arrow.up.left", label: "退出全屏") { leaveFullscreen() }
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 38)
                }
            }
            .frame(maxHeight: .infinity)

            if showMousePad {
                VirtualMousePad(client: client, dragLocked: $dragLocked)
                    .frame(height: 112)
                    .background(.thinMaterial)
            }

            if !isFullscreen {
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
        .ignoresSafeArea(.container, edges: isFullscreen ? .all : Edge.Set())
    }

    private func enterFullscreen() {
        showMousePad = false
        isFullscreen = true
        nextScreenCommand(fit: true)
        OrientationManager.requestLandscape()
    }

    private func leaveFullscreen() {
        isFullscreen = false
        OrientationManager.releaseLandscape()
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

    private func floatingButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    ContentView()
        .environmentObject(RemoteClient())
        .environmentObject(ConnectionHistoryStore())
}
