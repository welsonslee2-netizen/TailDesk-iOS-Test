# TailDesk iOS 0.7

原生 SwiftUI/UIKit 客户端，连接电脑端显示的 `Tailscale IPv4:手机端口`。

## 构建

1. 在 macOS 安装 Xcode 15 或更高版本。
2. 安装 XcodeGen：`brew install xcodegen`。
3. 在本目录运行 `xcodegen generate`。
4. 打开 `TailDeskMobile.xcodeproj`，在 Signing & Capabilities 选择自己的 Team。
5. 选择真机后运行，或用 Product > Archive 导出签名 App。

当前版本要求 iOS 16+。HTTP/WebSocket 只允许 App 内部校验通过的 Tailscale CGNAT IPv4；传输层由 Tailscale 加密，不应把电脑端口转发到公网。

0.7 新增不透明 App 图标、Keychain 密码历史、电脑名/IP 历史选择，以及横屏沉浸式全屏控制。进入全屏时虚拟鼠标默认隐藏，可通过右上角按钮随时调出；双指缩放和移动继续可用。

0.6 版先验证登录 Cookie 与 WebSocket 握手；长连接不可用时自动切换 HTTP 兼容模式。远程控制页提供独立虚拟鼠标触控板，并通过原生输入法发送中文、英文、退格、回车、Tab 和 Esc。

## 没有 Mac

仓库根目录已提供 `.github/workflows/ios-unsigned-ipa.yml`。将源码上传 GitHub 后，可在 Actions 手动运行 `Build TailDesk iOS IPA`，下载未签名 IPA，再按根目录 `IOS_WINDOWS_INSTALL.md` 使用 Windows AltServer 完成个人签名和真机安装。

