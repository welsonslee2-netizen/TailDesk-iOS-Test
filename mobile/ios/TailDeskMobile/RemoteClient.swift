import Foundation
import ImageIO
import UIKit

@MainActor
final class RemoteClient: ObservableObject {
    @Published var frame: UIImage?
    @Published var status = "尚未连接"
    @Published var connected = false
    @Published var computer = ""
    @Published var computerMac = ""
    @Published var rtt = 0

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var baseURL: URL?
    private var csrf = ""
    private var heartbeat: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var decoderTask: Task<Void, Never>?
    private var httpFlushTask: Task<Void, Never>?
    private var moveFlushTask: Task<Void, Never>?
    private var httpQueue = [[String: Any]]()
    private var pendingFrameData: Data?
    private var pendingMove: [String: Any]?
    private var httpMode = false
    private var lastPing = Date()
    private var selectedQuality = -1
    private var retryCount = 0
    private var manualDisconnect = false
    @Published private(set) var pointerX = 32768
    @Published private(set) var pointerY = 32768

    private struct LoginReply: Decodable { let csrf: String; let computer: String; let mac: String? }
    private struct ErrorReply: Decodable { let error: String }

    func connect(endpoint: String, password: String) async {
        disconnect(logout: false)
        manualDisconnect = false
        retryCount = 0
        do {
            let address = try Self.parse(endpoint)
            baseURL = address
            status = "正在验证密码…"
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 8
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpCookieStorage = .shared
            configuration.httpShouldSetCookies = true
            let currentSession = URLSession(configuration: configuration)
            session = currentSession

            var request = URLRequest(url: address.appendingPathComponent("login"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
            let (data, response) = try await currentSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError("登录响应无效") }
            guard http.statusCode == 200 else { throw ClientError(Self.serverError(data, fallback: "密码验证失败（\(http.statusCode)）")) }
            let login = try JSONDecoder().decode(LoginReply.self, from: data)
            csrf = login.csrf
            computer = login.computer
            computerMac = login.mac ?? ""
            try await verifySession(session: currentSession, address: address)
            do {
                try await openSocket(session: currentSession, address: address)
            } catch {
                startHTTPMode(session: currentSession, address: address)
            }
        } catch {
            status = error.localizedDescription
            connected = false
        }
    }

    private func verifySession(session: URLSession, address: URL) async throws {
        let request = URLRequest(url: address.appendingPathComponent("session"))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError("会话验证响应无效") }
        guard http.statusCode == 200 else {
            throw ClientError(Self.serverError(data, fallback: "会话 Cookie 验证失败（\(http.statusCode)）"))
        }
    }

    private func openSocket(session: URLSession, address: URL) async throws {
        var parts = URLComponents(url: address.appendingPathComponent("stream"), resolvingAgainstBaseURL: false)!
        parts.scheme = "ws"
        guard let url = parts.url else { throw ClientError("长连接地址无效") }
        var request = URLRequest(url: url)
        request.setValue("taildesk.\(csrf)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        if let cookies = session.configuration.httpCookieStorage?.cookies(for: address), !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            request.setValue(fields["Cookie"], forHTTPHeaderField: "Cookie")
        }
        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        guard socket === task else { throw ClientError("长连接已取消") }
        httpMode = false
        connected = true
        status = "已连接 · \(computer) · WebSocket"
        quality(selectedQuality)
        receiver = Task { [weak self] in await self?.receiveLoop(task) }
        heartbeat = Task { [weak self] in await self?.heartbeatLoop(task) }
    }

    private func startHTTPMode(session: URLSession, address: URL) {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        httpMode = true
        connected = true
        status = "已连接 · \(computer) · 兼容模式"
        frameTask?.cancel()
        frameTask = Task { [weak self] in await self?.httpFrameLoop(session: session, address: address) }
    }

    private func httpFrameLoop(session: URLSession, address: URL) async {
        var failures = 0
        while !Task.isCancelled, connected, httpMode {
            do {
                var request = URLRequest(url: address.appendingPathComponent("frame"))
                request.timeoutInterval = 8
                request.setValue(selectedQuality == 0 ? "text" : "smooth", forHTTPHeaderField: "X-TailDesk-Quality")
                let started = Date()
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      data.count <= 8 * 1024 * 1024,
                      let image = await Self.decodeImage(data) else {
                    throw ClientError("兼容模式画面响应无效")
                }
                frame = image
                failures = 0
                rtt = max(0, Int(Date().timeIntervalSince(started) * 1000))
                status = "已连接 · \(computer) · 兼容模式 · \(rtt) ms"
                try await Task.sleep(nanoseconds: 35_000_000)
            } catch {
                if Task.isCancelled { return }
                failures += 1
                status = "网络波动（\(failures)/5）：\(error.localizedDescription)"
                if failures >= 5 {
                    connected = false
                    status = "连接已中断：\(error.localizedDescription)"
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(failures) * 500_000_000)
            }
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled, socket === task {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    guard data.count <= 8 * 1024 * 1024 else { throw ClientError("远程画面数据过大") }
                    enqueueFrame(data)
                    retryCount = 0
                    send(["type": "ack"])
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if json["type"] as? String == "pong" {
                            retryCount = 0
                            rtt = max(0, Int(Date().timeIntervalSince(lastPing) * 1000))
                            status = "已连接 · \(computer) · RTT \(rtt) ms"
                            if selectedQuality == -1 { sendQuality(rtt > 140 ? 2 : 1) }
                        } else if json["type"] as? String == "error", let message = json["message"] as? String {
                            status = message
                        } else if json["type"] as? String == "clipboard", let value = json["text"] as? String,
                                  !value.isEmpty, value.utf8.count <= 256 * 1024 {
                            UIPasteboard.general.string = value
                            status = "已同步被控电脑剪贴板，可切换到其他 App 粘贴"
                        }
                    }
                @unknown default: break
                }
            }
        } catch {
            if socket === task { connectionEnded(error.localizedDescription) }
        }
    }

    private func heartbeatLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled, socket === task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled || socket !== task { return }
            lastPing = Date()
            send(["type": "ping"])
        }
    }

    func quality(_ mode: Int) {
        selectedQuality = mode
        sendQuality(mode < 0 ? 2 : mode)
    }

    private func sendQuality(_ mode: Int) { send(["type": "quality", "mode": mode]) }

    func mouse(x: Int, y: Int, action: Int, wheel: Int = 0) {
        pointerX = min(65535, max(0, x)); pointerY = min(65535, max(0, y))
        let event: [String: Any] = ["type": "mouse", "x": pointerX, "y": pointerY, "action": action, "wheel": wheel]
        if action == 0 && wheel == 0 {
            pendingMove = event
            scheduleMoveFlush()
        } else {
            flushPendingMove()
            send(event)
        }
    }

    func movePointer(dx: CGFloat, dy: CGFloat) {
        let speed = max(abs(dx), abs(dy)) > 10 ? 220.0 : 125.0
        pointerX = min(65535, max(0, pointerX + Int(dx * speed)))
        pointerY = min(65535, max(0, pointerY + Int(dy * speed)))
        send(["type": "mouse", "x": pointerX, "y": pointerY, "action": 0, "wheel": 0])
    }

    func click(x: Int, y: Int, right: Bool = false) {
        mouse(x: x, y: y, action: right ? 3 : 1)
        mouse(x: x, y: y, action: right ? 4 : 2)
    }

    func key(_ code: Int) {
        send(["type": "key", "key": code, "down": true])
        send(["type": "key", "key": code, "down": false])
    }

    func clickCurrent(right: Bool = false) { click(x: pointerX, y: pointerY, right: right) }
    func leftButton(down: Bool) { mouse(x: pointerX, y: pointerY, action: down ? 1 : 2) }
    func scroll(_ amount: Int) { mouse(x: pointerX, y: pointerY, action: 7, wheel: amount) }

    func text(_ value: String) {
        guard !value.isEmpty else { return }
        var start = value.startIndex
        while start < value.endIndex {
            let end = value.index(start, offsetBy: 128, limitedBy: value.endIndex) ?? value.endIndex
            send(["type": "text", "text": String(value[start..<end])])
            start = end
        }
    }

    func release() { send(["type": "release"]) }

    private func send(_ object: [String: Any]) {
        guard connected else { return }
        if httpMode {
            if httpQueue.count >= 96 { httpQueue.removeAll(); httpQueue.append(["type": "release"]) }
            httpQueue.append(object)
            scheduleHTTPFlush()
            return
        }
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            if let error { Task { @MainActor in self?.connectionEnded(error.localizedDescription) } }
        }
    }

    private func scheduleMoveFlush() {
        guard moveFlushTask == nil else { return }
        moveFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000)
            guard !Task.isCancelled else { return }
            self?.moveFlushTask = nil
            self?.flushPendingMove()
        }
    }

    private func flushPendingMove() {
        guard let event = pendingMove else { return }
        pendingMove = nil
        send(event)
    }

    private func enqueueFrame(_ data: Data) {
        pendingFrameData = data
        guard decoderTask == nil else { return }
        decoderTask = Task { [weak self] in await self?.decodePendingFrames() }
    }

    private func decodePendingFrames() async {
        while !Task.isCancelled, let data = pendingFrameData {
            pendingFrameData = nil
            if let image = await Self.decodeImage(data) { frame = image }
        }
        decoderTask = nil
        if pendingFrameData != nil { enqueueFrame(pendingFrameData!) }
    }

    nonisolated private static func decodeImage(_ data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                autoreleasepool {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 4096, height <= 4096 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let options: [CFString: Any] = [
                        kCGImageSourceShouldCache: true,
                        kCGImageSourceShouldCacheImmediately: true
                    ]
                    guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: image))
                }
            }
        }
    }

    private func scheduleHTTPFlush() {
        guard httpFlushTask == nil else { return }
        httpFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            await self?.flushHTTPQueue()
        }
    }

    private func flushHTTPQueue() async {
        httpFlushTask = nil
        guard connected, httpMode, let address = baseURL, let currentSession = session, !httpQueue.isEmpty else { return }
        let count = min(32, httpQueue.count)
        let events = Array(httpQueue.prefix(count))
        httpQueue.removeFirst(count)
        let body: [String: Any] = events.count == 1 ? events[0] : ["type": "batch", "events": events]
        do {
            var request = URLRequest(url: address.appendingPathComponent("input"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(csrf, forHTTPHeaderField: "X-TailDesk-CSRF")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await currentSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw ClientError(Self.serverError(data, fallback: "输入发送失败"))
            }
        } catch {
            status = "输入发送失败：\(error.localizedDescription)"
        }
        if !httpQueue.isEmpty { scheduleHTTPFlush() }
    }

    func disconnect(logout: Bool = true) {
        manualDisconnect = true
        release()
        let address = baseURL
        let currentSession = session
        let token = csrf
        receiver?.cancel(); heartbeat?.cancel(); reconnectTask?.cancel(); frameTask?.cancel(); decoderTask?.cancel(); httpFlushTask?.cancel(); moveFlushTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil; receiver = nil; heartbeat = nil; reconnectTask = nil; frameTask = nil; decoderTask = nil; httpFlushTask = nil; moveFlushTask = nil
        httpQueue.removeAll(); pendingFrameData = nil; pendingMove = nil; httpMode = false
        connected = false; frame = nil
        if logout, let address, let currentSession, !token.isEmpty {
            Task {
                var request = URLRequest(url: address.appendingPathComponent("logout"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(token, forHTTPHeaderField: "X-TailDesk-CSRF")
                request.httpBody = Data("{}".utf8)
                _ = try? await currentSession.data(for: request)
            }
        }
        csrf = ""; status = "已断开"
    }

    private func connectionEnded(_ message: String) {
        guard connected else { return }
        connected = false
        receiver?.cancel(); heartbeat?.cancel()
        status = "连接已中断：\(message) · 正在重连"
        socket = nil
        guard !manualDisconnect, let address = baseURL, let currentSession = session else { return }
        retryCount += 1
        let delay = min(15, 1 << min(4, retryCount - 1))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard let self, !Task.isCancelled, !self.manualDisconnect, !self.connected else { return }
            do { try await self.openSocket(session: currentSession, address: address) }
            catch { self.startHTTPMode(session: currentSession, address: address) }
        }
    }

    private static func parse(_ endpoint: String) throws -> URL {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = raw.contains(":") ? raw : raw + ":59011"
        let pieces = full.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, let port = Int(pieces[1]), (1024...65535).contains(port) else {
            throw ClientError("请输入 Tailscale 或局域网 IPv4:端口，例如 192.168.1.20:59011")
        }
        let octets = pieces[0].split(separator: ".").compactMap { Int($0) }
        let isTail = octets.count == 4 && octets[0] == 100 && (64...127).contains(octets[1])
        let isPrivate = octets.count == 4 && (octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168))
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }),
              octets[0] == 127 || isTail || isPrivate else {
            throw ClientError("仅连接 Tailscale、局域网 IPv4 或 127.0.0.1")
        }
        return URL(string: "http://\(pieces[0]):\(port)/")!
    }

    private static func serverError(_ data: Data, fallback: String) -> String {
        (try? JSONDecoder().decode(ErrorReply.self, from: data).error) ?? fallback
    }

    private struct ClientError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

