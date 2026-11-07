# TailDesk 0.13 验证记录

验证日期：2026-11-07。

- Windows x64 本机构建成功，使用系统 .NET Framework C# 编译器。EasyTier 2.6.4 为独立随包组件。
- `test.ps1` 执行成功，89 项检查通过。逐项结果在 `artifacts/self-test.txt`。
- EasyTier 官方 Release ZIP 的 SHA-256 已核对为 `27af91e270e554709b048bd32327fefd2dfce5062ae1e8701af7550c6f525f84`。
- 新增检查覆盖 P2P 设置默认关闭、DPAPI 密钥持久化和 iOS `TDNET1` 配置导出。
- 本机实际进入 DXGI / D3D11 GPU 采集路径，原分辨率首帧 PNG 约 263 KB、84 ms；该值包含采集及编码，不代表跨机延迟或持续帧率。JPEG/PNG 仍为 CPU 编码。
- 新增检查：无损 PNG、高清 JPEG、尺寸验证、密码直接控制、错误密码拒绝、临时码保留确认、电脑名、画质切换、限速、历史及 DPAPI 加密。
- 已修复帧确认期间断线导致延迟释放按键的问题，专门在首帧确认前断开验证立即释放。
- 文件集成测试：真实 TCP 同时双向传输、9 MiB + 17 字节随机文件、零字节文件、中文文件名、SHA-256、拒绝接收、图像和键盘并行处理。
- 文件异常测试：路径穿越、Windows 保留名、NTFS ADS、错误校验、乱序块、断线残片清理。
- 输入路径使用 DryRun 和原生调用替身；没有对用户当前桌面注入实际按键和鼠标，因此不将这些测试视为真实跨机输入验证。
- 手机测试使用真实本机 HTTP/WebSocket：认证 Cookie 与 CSRF 子协议、二进制画面、帧确认、Unicode 输入、心跳、HTTP 回退、非法坐标、登出及电脑/手机会话互斥均通过。
- Android 维持 0.12 旧产物，本次未改动或重新交付。
- `node check-mobile.cjs` 检查手机 JavaScript 语法及元素引用通过。
- 用户已确认旧版跨机控制可用。0.13 的 EasyTier 跨运营商 P2P、iOS 真机签名/触控、不同 GPU 回退、高 DPI、长时间和慢网体验仍需实测。无人值守需要已登录普通桌面且 TailDesk 正在运行。

自动测试最初被执行沙箱阻止访问本机套接字，随后在获准的沙箱外执行通过；这与程序本身的 TCP 连接逻辑无关。

交付包：`dist/TailDesk-0.13-win-x64.zip`、`dist/TailDesk-iOS-0.13-source.zip` 和 GitHub Actions 生成的 `TailDesk-unsigned.ipa`。新版 Windows 输出在 `bin/0.13`。
