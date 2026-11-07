# TailDesk iOS：Windows 免费测试方案

该方案使用 GitHub Actions 的 macOS 构建机生成未签名 IPA，再由 Windows 上的 AltServer 使用个人 Apple Account 签名并安装到 iPhone。个人签名通常需要每 7 天刷新。

## 1. 上传源码到 GitHub

创建一个 GitHub 仓库，建议选择 Private。仓库根目录必须至少包含：

```text
.github/workflows/ios-unsigned-ipa.yml
mobile/ios/
scripts/build-ios-unsigned.sh
```

可以上传整个 TailDesk 项目，也可以解压 `dist/TailDesk-iOS-0.13-source.zip` 后上传其中内容。

## 2. 云端生成 IPA

1. 打开 GitHub 仓库的 `Actions` 页面。
2. 左侧选择 `Build TailDesk iOS IPA`。
3. 点击 `Run workflow`，再次确认运行。
4. 等待 `Build unsigned IPA` 全部变绿。
5. 在运行详情底部的 `Artifacts` 下载 `TailDesk-iOS-unsigned-*`。
6. 解压后得到 `TailDesk-unsigned.ipa`、SHA-256 和构建信息。

工作流会实际编译 arm64 iPhone App，并检查 Info.plist、最低 iOS 版本、可执行文件、IPA ZIP 完整性和 SHA-256。产物在 GitHub 保留 7 天。

## 3. Windows 安装到 iPhone

1. 从 Apple 官网安装 Windows 版 iTunes 和 iCloud。
2. 从 AltStore 官网安装 AltServer for Windows。
3. USB 连接 iPhone，解锁并选择“信任此电脑”。
4. 启动 AltServer；按住 `Shift` 点击任务栏 AltServer 图标。
5. 选择 `Sideload .ipa...`，再选择 `TailDesk-unsigned.ipa`。
6. 按 AltServer 提示使用个人 Apple Account 完成签名。
7. iPhone 进入“设置 > 隐私与安全性 > 开发者模式”，启用并重启。
8. 如系统提示，再进入“设置 > 通用 > VPN 与设备管理”信任对应开发者。

AltServer 应保持运行，并与 iPhone 位于同一 Wi-Fi，以便自动刷新个人签名；也可以每周通过 USB 手动刷新。

## 4. 连接 TailDesk 电脑端

1. iPhone 和电脑位于同一局域网、同一 EasyTier 网络或同一可互访的 Tailscale 网络。
2. 电脑端 TailDesk 0.13 启用“无人值守密码”和“手机入口”，然后开启被控。
3. App 地址填写 `10.x.x.x:59011`、`192.168.x.x:59011` 或 `100.x.x.x:59011`，不要填写 `http://`。
4. 输入无人值守密码并连接。
5. 首次出现本地网络权限提示时选择允许。

## 常见问题

- `No profiles for ... were found`：云端步骤必须保留 `CODE_SIGNING_ALLOWED=NO`；签名由 AltServer 在 Windows 完成。
- GitHub 构建失败：打开失败步骤并下载日志，不要只截取最后一行。
- App 打不开：确认已开启开发者模式、开发者已信任，且 7 天个人签名未过期。
- 连接超时：确认手机 Tailscale 在线、填写的是电脑窗口显示的手机端口、Windows 防火墙允许该端口。

国内 P2P 的完整配置、EasyTier iOS 限制与故障排查见 `TAILDESK_013_DEPLOYMENT.md`。

