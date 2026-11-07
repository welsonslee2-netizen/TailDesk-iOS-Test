# TailDesk 0.13 部署与使用教程

## 1. 本版组成

TailDesk 0.13 包含两个交付端：

- Windows x64：`TailDesk.exe`、EasyTier 2.6.4 核心、虚拟网卡运行库和说明文档放在同一个 ZIP 中。无需另装 Tailscale 或 EasyTier Windows 客户端。
- iOS 16+：TailDesk 0.13 原生 App。负责画面、键盘、触控、虚拟鼠标、横屏、唤醒和剪贴板同步。

Windows 已实现单软件集成。iOS 的虚拟网卡必须由 Apple `Network Extension` 扩展创建；个人免费签名通常没有这一 entitlement，因此当前需要同时运行 EasyTier iOS。TailDesk 已提供配置代码导入，减少手工抄写。具备付费 Apple Developer Team 与 Network Extension 权限后，可把网络扩展作为第二个 target 合入同一 IPA。

## 2. 网络选择

推荐顺序：

1. 同一局域网：直接使用 `192.168.x.x` 等地址，延迟最低。
2. 异地控制：使用本版集成的 EasyTier，优先尝试 P2P 直连。
3. 现有 Tailscale 网络：仍可使用 `100.64.0.0/10` 地址，不影响旧环境。

EasyTier 公共节点主要负责发现和打洞。如果两端网络允许 UDP/TCP 打洞，远程画面走点对点链路；打洞失败时才经公共节点转发。公共共享节点没有带宽保障，长期使用可在国内云主机上运行自己的发现节点。

## 3. Windows 安装

1. 解压 `TailDesk-0.13-win-x64.zip` 到固定目录，例如 `D:\TailDesk`。不要只复制 `TailDesk.exe`，必须保留旁边的 `easytier` 文件夹。
2. 右键 `TailDesk.exe`，选择“以管理员身份运行”。EasyTier 首次创建虚拟网卡需要管理员权限。
3. Windows 防火墙询问时，至少允许“专用网络”。异地 P2P 使用时也允许 TailDesk 和 `easytier-core.exe` 通过防火墙。
4. 点击“控制 / 国内 P2P 设置”。
5. 设置 12–128 位无人值守密码，勾选“启用无人值守密码控制”和“同时开启 iOS / 安卓浏览器入口”。
6. 在“国内 P2P 组网”中点击“生成新网络”。默认会生成随机网络名、随机强密钥和 `10.126.0.1` 本机虚拟 IP。
7. 勾选“启动 TailDesk 时自动启动国内 P2P”，保存。主窗口应显示“国内 P2P 运行中”。
8. 地址列表出现 `10.126.0.1 (EasyTier 国内 P2P)` 后选择它，点击“开启被控”。

第二台 Windows 电脑加入同一网络时，网络名称、网络密钥和公共节点保持一致，但虚拟 IP 改为未占用地址，例如 `10.126.0.2`。

### 自动运行

设置页勾选“启动 TailDesk 时自动开启被控”后，下次启动会自动监听上次地址。若希望无人登录也能工作，后续版本需要把主机拆成 Windows Service，并以 SYSTEM 运行；当前桌面程序应在用户登录后启动。Windows 睡眠期间任何桌面远控程序都不运行，唤醒依赖局域网 Wake-on-LAN。

## 4. iOS 0.13 安装

### 4.1 GitHub Actions 构建

1. 将 `TailDesk-iOS-0.13-source.zip` 解压并上传到 GitHub 仓库根目录。
2. 打开仓库 `Actions`，选择 `Build TailDesk iOS IPA`。
3. 点击 `Run workflow`。
4. 任务完成后下载 `TailDesk-iOS-unsigned-*` artifact，解压得到 `TailDesk-unsigned.ipa`。

### 4.2 Windows 签名安装

1. 安装 Apple 官网版本的 iTunes 与 iCloud，再安装 AltServer。
2. USB 连接并解锁 iPhone，在手机上选择“信任此电脑”。
3. 启动 AltServer，按住 `Shift` 点击任务栏图标，选择 `Sideload .ipa...`。
4. 选择 `TailDesk-unsigned.ipa`，按提示使用 Apple Account 完成个人签名。
5. iPhone 打开“设置 > 隐私与安全性 > 开发者模式”，开启并重启。
6. 如有提示，在“设置 > 通用 > VPN 与设备管理”中信任开发者。

个人免费签名通常 7 天到期。AltServer 与 iPhone 在同一 Wi-Fi 时可刷新，也可每周 USB 刷新。

## 5. iPhone 加入国内 P2P 网络

1. Windows TailDesk 打开“控制 / 国内 P2P 设置”，点击“复制 iOS 配置”。
2. 将 `TDNET1:...` 配置代码发送到 iPhone，并复制到系统剪贴板。配置含网络密钥，应只通过自己的可信通道传递。
3. 在 iPhone 安装 EasyTier iOS，创建并启用一个网络。
4. 打开 TailDesk 0.13，点击“国内 P2P 配置” > “从剪贴板导入 Windows 配置”。
5. 按页面逐项复制网络名称、网络密钥、公共节点和建议的 iPhone 虚拟 IP到 EasyTier iOS。
6. EasyTier iOS 显示连接成功后，回到 TailDesk，点击“使用 10.126.0.1:59011”。
7. 输入 Windows 端无人值守密码并连接。

若 App Store 地区提供 EasyTier iOS，可直接安装官方版本。GitHub Nightly IPA 带 Network Extension 与 App Group entitlement，普通 AltServer 个人签名不一定能重签这些权限；这时需要对应 Apple 开发者权限或支持保留 entitlement 的安装环境。

## 6. 日常控制

- 横屏：连接后点击“全屏”，自动切换横屏；右上角可唤起键盘、虚拟鼠标或退出全屏。
- 缩放：双指缩放，放大后双指移动；工具栏也提供“适应”和“原尺寸”。
- 鼠标：虚拟触控板移动指针，单击左键，双指/工具按钮滚动；全屏默认隐藏，按右上角鼠标按钮调出。
- 输入：点击键盘按钮唤起 iOS 输入法，支持中文、英文、退格、回车、Tab 和 Esc。
- 剪贴板：被控 Windows 上复制的新文本会同步到 iPhone 系统剪贴板，可切换到其他 App 粘贴。单次文本上限 256 KiB。
- 唤醒：点击“连接电脑”会先发送一次 Wake-on-LAN，再自动重试。要求 iPhone 与电脑处于同一广播域，或局域网内存在能代发 WOL 的在线节点。

## 7. 性能设置

1. 优先使用“自动画质”；文字看不清时切换“文字清晰”，带宽较差时选择“流畅省流量”。
2. 在 EasyTier 中保持延迟优先和多线程。本版 Windows 集成核心默认开启这两项。
3. 判断是否 P2P：在 Windows 安装包目录运行：

   ```powershell
   .\easytier\easytier-cli.exe peer
   ```

   观察到两端直接连接地址时为 P2P；只有公共节点路径时为中继。
4. 中继卡顿时，在双方路由器启用 UPnP，避免多层 NAT，或在国内云主机部署仅用于发现的 EasyTier 节点。

## 8. 自建节点

有公网 IP 的国内 VPS 可直接运行：

```bash
./easytier-core --relay-network-whitelist --relay-all-peer-rpc
```

然后把两端“公共节点”改为该主机地址，例如 `tcp://VPS_IP:11010`。此模式主要做节点发现并帮助建立 P2P，带宽通常不经过 VPS，费用主要是最低配置实例和少量控制流量。家用电脑里的虚拟机只有在宿主机具备公网可达端口、端口映射和持续在线时才等价于 VPS；普通 NAT 后的虚拟机不具备公网中转能力。

## 9. 故障排查

- 国内 P2P 启动失败：确认以管理员身份运行；确认 ZIP 中 `easytier` 文件夹完整；检查杀毒软件隔离记录。
- 虚拟 IP 不出现：停止 P2P再启动，等待 3–10 秒刷新地址；检查 Windows 网络适配器中是否出现 EasyTier/Wintun。
- iOS 连接超时：先确认 EasyTier iOS 已连接，再从 iPhone ping/测试电脑虚拟 IP；端口应为 `59011`，Windows 主机端必须已“开启被控”。
- 画面很卡：确认没有走公共中继；将画质切到“流畅”；双方尽量使用有线或 5 GHz/6 GHz Wi-Fi。
- 锁屏显示状态画面：普通用户进程对 Winlogon 安全桌面的采集和输入受 Windows 会话隔离限制。完整支持开机登录界面需要 SYSTEM 服务与安全桌面捕获组件。
- 剪贴板未同步：当前方向是被控 Windows到控制端；复制后保持会话在线，iOS 收到“已同步被控电脑剪贴板”提示后再切换 App 粘贴。
- AltServer 安装超时：USB 保持连接和解锁，关闭冲突的代理/VPN，重启 Apple Mobile Device Service 后再装。

## 10. 安全与数据位置

- 无人值守密码只保存 PBKDF2 派生凭证。
- EasyTier 网络密钥由 Windows 当前用户 DPAPI 加密保存，不写入明文设置文件，也不放入进程命令行。
- 历史连接密码在 iOS Keychain 中保存。
- TailDesk 端口仅接受 Tailscale、RFC1918 私有地址或本机回环地址，不应映射到公网。
- EasyTier 使用 LGPL v3，官方核心版本、哈希、许可证和上游地址位于安装包 `easytier` 目录。
