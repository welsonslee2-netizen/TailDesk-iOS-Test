import SwiftUI
import UIKit

struct NetworkSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var endpoint: String
    @State private var network = ""
    @State private var secret = ""
    @State private var peer = "tcp://public.easytier.top:11010"
    @State private var computerIP = ""
    @State private var phoneIP = ""
    @State private var message = "先在 Windows TailDesk 设置中复制 iOS 配置代码。"

    var body: some View {
        NavigationStack {
            Form {
                Section("导入配置") {
                    Button("从剪贴板导入 Windows 配置") { importCode() }
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if !network.isEmpty {
                    Section("EasyTier iOS 中填写") {
                        copyRow("网络名称", value: network)
                        copyRow("网络密钥", value: secret, privateValue: true)
                        copyRow("公共节点", value: peer)
                        copyRow("iPhone 虚拟 IP", value: phoneIP)
                    }
                    Section("TailDesk 连接地址") {
                        Text("电脑虚拟 IP：\(computerIP)")
                        Button("使用 \(computerIP):59011") {
                            endpoint = computerIP + ":59011"
                            dismiss()
                        }
                    }
                }
                Section("使用顺序") {
                    Text("1. 在 iPhone 安装并打开 EasyTier iOS。")
                    Text("2. 新建网络，逐项复制上面的名称、密钥、公共节点和 iPhone 虚拟 IP。")
                    Text("3. EasyTier 显示已连接后，返回 TailDesk，使用电脑虚拟 IP 连接。")
                    Text("每台设备的虚拟 IP 必须不同；网络名称、密钥和公共节点必须相同。")
                }
                Section("iOS 系统限制") {
                    Text("系统级虚拟网卡由 Network Extension 提供，需要相应的 Apple 签名权限。TailDesk 负责远程控制，EasyTier iOS 负责建立虚拟网络。")
                    Link("查看 EasyTier iOS 官方项目", destination: URL(string: "https://github.com/EasyTier/EasyTier-iOS")!)
                }
            }
            .navigationTitle("国内 P2P 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func copyRow(_ title: String, value: String, privateValue: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(privateValue ? String(repeating: "•", count: min(16, value.count)) : value)
                    .font(.system(.body, design: .monospaced)).lineLimit(2)
            }
            Spacer()
            Button("复制") { UIPasteboard.general.string = value }
        }
    }

    private func importCode() {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("TDNET1:"),
              let data = Data(base64Encoded: String(raw.dropFirst(7))),
              let text = String(data: data, encoding: .utf8) else {
            message = "剪贴板中没有有效的 TDNET1 配置代码。"
            return
        }
        let values = text.components(separatedBy: "\n")
        guard values.count == 4, !values[0].isEmpty, values[1].count >= 12 else {
            message = "配置代码内容不完整。"
            return
        }
        network = values[0]; secret = values[1]; peer = values[2]; computerIP = values[3]
        phoneIP = Self.nextAddress(after: computerIP) ?? "请填写另一未占用私有 IP"
        message = "配置已导入。请按下面顺序复制到 EasyTier iOS。"
    }

    private static func nextAddress(after address: String) -> String? {
        var parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return nil }
        parts[3] = parts[3] >= 254 ? max(2, parts[3] - 1) : parts[3] + 1
        return parts.map(String.init).joined(separator: ".")
    }
}
