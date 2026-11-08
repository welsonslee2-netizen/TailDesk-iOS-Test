import CryptoKit
import Foundation

enum SecureRecordKind: UInt8 {
    case frameJPEG = 10
    case framePNG = 19
    case json = 23
}

final class MobileSessionCipher {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let sendPrefix: Data
    private let receivePrefix: Data
    private var sendSequence: UInt64 = 0
    private var receiveSequence: UInt64 = 0

    init(passwordKey: Data, serverNonce: Data, clientNonce: Data) {
        let salt = serverNonce + clientNonce
        let materialKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passwordKey),
            salt: salt,
            info: Data("TailDesk/15/mobile".utf8),
            outputByteCount: 72
        )
        let material = materialKey.withUnsafeBytes { Data($0) }
        sendKey = SymmetricKey(data: material[0..<32])
        sendPrefix = Data(material[32..<36])
        receiveKey = SymmetricKey(data: material[36..<68])
        receivePrefix = Data(material[68..<72])
    }

    func seal(kind: SecureRecordKind, payload: Data) throws -> Data {
        let sequence = sendSequence
        sendSequence &+= 1
        let header = Self.header(sequence)
        let nonce = try AES.GCM.Nonce(data: sendPrefix + Self.sequenceBytes(sequence))
        let box = try AES.GCM.seal(Data([kind.rawValue]) + payload, using: sendKey, nonce: nonce, authenticating: header)
        return header + box.ciphertext + box.tag
    }

    func open(_ record: Data) throws -> (SecureRecordKind, Data) {
        guard record.count >= 26, record[record.startIndex] == 1 else { throw CryptoError("加密记录格式无效") }
        let sequence = Self.readSequence(record.dropFirst().prefix(8))
        guard sequence == receiveSequence else { throw CryptoError("加密记录序号不连续") }
        let header = Data(record.prefix(9))
        let encrypted = Data(record.dropFirst(9).dropLast(16))
        let tag = Data(record.suffix(16))
        let nonce = try AES.GCM.Nonce(data: receivePrefix + Self.sequenceBytes(sequence))
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: encrypted, tag: tag)
        let plain = try AES.GCM.open(box, using: receiveKey, authenticating: header)
        guard let first = plain.first, let kind = SecureRecordKind(rawValue: first) else { throw CryptoError("加密消息类型无效") }
        receiveSequence &+= 1
        return (kind, Data(plain.dropFirst()))
    }

    private static func header(_ sequence: UInt64) -> Data { Data([1]) + sequenceBytes(sequence) }
    private static func sequenceBytes(_ sequence: UInt64) -> Data {
        Data((0..<8).map { UInt8(truncatingIfNeeded: sequence >> UInt64($0 * 8)) })
    }
    private static func readSequence<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        bytes.enumerated().reduce(0) { $0 | (UInt64($1.element) << UInt64($1.offset * 8)) }
    }

    struct CryptoError: LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }
}

enum MobileCrypto {
    static func derivePassword(_ password: String, salt: Data, iterations: Int) async -> Data {
        await Task.detached(priority: .userInitiated) {
            pbkdf2(password: Data(password.utf8), salt: salt, iterations: iterations)
        }.value
    }

    static func proof(key: Data, role: String, id: String, serverNonce: Data, clientNonce: Data) -> Data {
        let message = Data("TailDesk/mobile/15/\(role)/\(id)".utf8) + serverNonce + clientNonce
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int) -> Data {
        let key = SymmetricKey(data: password)
        var block = salt + Data([0, 0, 0, 1])
        var current = Data(HMAC<SHA256>.authenticationCode(for: block, using: key))
        var result = current
        if iterations > 1 {
            for _ in 2...iterations {
                current = Data(HMAC<SHA256>.authenticationCode(for: current, using: key))
                for index in result.indices { result[index] ^= current[index] }
            }
        }
        block.resetBytes(in: block.indices)
        return result
    }
}
