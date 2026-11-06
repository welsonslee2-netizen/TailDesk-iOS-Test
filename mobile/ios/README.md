# TailDesk iOS 0.5

原生 SwiftUI/UIKit 客户端，连接电脑端显示的 `Tailscale IPv4:手机端口`。

## 构建

1. 在 macOS 安装 Xcode 15 或更高版本。
2. 安装 XcodeGen：`brew install xcodegen`。
3. 在本目录运行 `xcodegen generate`。
4. 打开 `TailDeskMobile.xcodeproj`，在 Signing & Capabilities 选择自己的 Team。
5. 选择真机后运行，或用 Product > Archive 导出签名 App。

当前版本要求 iOS 16+。HTTP/WebSocket 只允许 App 内部校验通过的 Tailscale CGNAT IPv4；传输层由 Tailscale 加密，不应把电脑端口转发到公网。

## 没有 Mac

仓库根目录已提供 `.github/workflows/ios-unsigned-ipa.yml`。将源码上传 GitHub 后，可在 Actions 手动运行 `Build TailDesk iOS IPA`，下载未签名 IPA，再按根目录 `IOS_WINDOWS_INSTALL.md` 使用 Windows AltServer 完成个人签名和真机安装。

