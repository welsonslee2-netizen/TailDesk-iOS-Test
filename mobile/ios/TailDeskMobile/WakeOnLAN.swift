import Foundation
import Darwin

enum WakeOnLAN {
    static func send(macAddress: String) throws {
        let mac = try parse(macAddress)
        var packet = Data(repeating: 0xff, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }

        let socketDescriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else { throw WakeError("创建 UDP 套接字失败") }
        defer { Darwin.close(socketDescriptor) }

        var enabled: Int32 = 1
        guard setsockopt(socketDescriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw WakeError("系统未允许局域网广播")
        }

        for target in broadcastTargets() {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr = in_addr(s_addr: target)
            for _ in 0..<3 {
                for port in [9, 7] {
                    address.sin_port = in_port_t(UInt16(port).bigEndian)
                    let sent = packet.withUnsafeBytes { bytes in
                        withUnsafePointer(to: &address) { pointer in
                            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                                Darwin.sendto(socketDescriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                    guard sent == packet.count else { throw WakeError("Wake-on-LAN 魔术包发送失败") }
                }
            }
        }
    }

    private static func broadcastTargets() -> [in_addr_t] {
        var targets = [inet_addr("255.255.255.255")]
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return targets }
        defer { freeifaddrs(interfaces) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  let netmask = entry.pointee.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name) == "en0" else { continue }
            let ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            let directed = (ip & mask) | ~mask
            if !targets.contains(directed) { targets.append(directed) }
        }
        return targets
    }

    private static func parse(_ value: String) throws -> [UInt8] {
        let compact = value.uppercased().filter { $0.isHexDigit }
        guard compact.count == 12 else { throw WakeError("请输入 12 位网卡 MAC，例如 AA:BB:CC:DD:EE:FF") }
        var bytes = [UInt8]()
        var index = compact.startIndex
        for _ in 0..<6 {
            let end = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<end], radix: 16) else { throw WakeError("MAC 地址格式错误") }
            bytes.append(byte); index = end
        }
        return bytes
    }

    private struct WakeError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
