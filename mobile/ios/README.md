# TailDesk iOS 0.11

原生 SwiftUI/UIKit 客户端，连接电脑端显示的 `Tailscale IPv4:手机端口`。

## 构建

1. 在 macOS 安装 Xcode 15 或更高版本。
2. 安装 XcodeGen：`brew install xcodegen`。
3. 在本目录运行 `xcodegen generate`。
4. 打开 `TailDeskMobile.xcodeproj`，在 Signing & Capabilities 选择自己的 Team。
5. 选择真机后运行，或用 Product > Archive 导出签名 App。

当前版本要求 iOS 16+。HTTP/WebSocket 只允许 App 内部校验通过的 Tailscale CGNAT IPv4；传输层由 Tailscale 加密，不应把电脑端口转发到公网。

0.7 新增不透明 App 图标、Keychain 密码历史、电脑名/IP 历史选择，以及横屏沉浸式全屏控制。进入全屏时虚拟鼠标默认隐藏，可通过右上角按钮随时调出；双指缩放和移动继续可用。

0.8 新增局域网 Wake-on-LAN：历史连接同时记录物理网卡 MAC，可在电脑睡眠时发送 UDP 魔术包。该功能要求手机与电脑位于同一局域网，并在电脑 BIOS/UEFI 与网卡电源管理中启用 Wake-on-LAN。

0.9 将画面解码移到后台线程，只渲染最新帧；自动画质优先使用低延迟档，兼容模式不再错误请求原分辨率 PNG，并合并高频鼠标移动事件。需要同步更新 Windows 主机端才能使用新的低延迟视频参数。

0.10 取消独立的重复唤醒按钮。点击“连接电脑”会先自动发送一次 Wake-on-LAN 魔术包，然后在约一分钟内自动等待并重试连接；电脑本来在线时仍会直接进入控制。

0.11 使用 iPhone Wi-Fi 地址和掩码计算定向广播并发送唤醒脉冲；连接成功后由电脑端回传物理网卡 MAC，避免历史记录保存错误地址。新增被控电脑文本剪贴板实时同步到 iOS 系统剪贴板。锁屏采集异常会显示有效状态画面并保持会话，不再把采集异常表现为图片解码失败。

0.6 版先验证登录 Cookie 与 WebSocket 握手；长连接不可用时自动切换 HTTP 兼容模式。远程控制页提供独立虚拟鼠标触控板，并通过原生输入法发送中文、英文、退格、回车、Tab 和 Esc。

## 没有 Mac

仓库根目录已提供 `.github/workflows/ios-unsigned-ipa.yml`。将源码上传 GitHub 后，可在 Actions 手动运行 `Build TailDesk iOS IPA`，下载未签名 IPA，再按根目录 `IOS_WINDOWS_INSTALL.md` 使用 Windows AltServer 完成个人签名和真机安装。

