import Foundation
import Security

struct SavedConnection: Codable, Identifiable, Hashable {
    let id: UUID
    var endpoint: String
    var computer: String
    var macAddress: String? = nil
    var lastConnectedAt: Date

    var title: String {
        let name = computer.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? endpoint : "\(name) · \(endpoint)"
    }
}

@MainActor
final class ConnectionHistoryStore: ObservableObject {
    @Published private(set) var entries = [SavedConnection]()

    private let defaultsKey = "taildesk.savedConnections.v1"
    private let keychainService = "com.taildesk.mobile.saved-connections"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([SavedConnection].self, from: data) {
            entries = decoded.sorted { $0.lastConnectedAt > $1.lastConnectedAt }
        }
    }

    func save(endpoint: String, computer: String, password: String, macAddress: String) {
        let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !password.isEmpty else { return }
        var entry = entries.first(where: { $0.endpoint.caseInsensitiveCompare(address) == .orderedSame })
            ?? SavedConnection(id: UUID(), endpoint: address, computer: computer, macAddress: nil, lastConnectedAt: Date())
        entry.endpoint = address
        entry.computer = computer
        let mac = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.macAddress = mac.isEmpty ? entry.macAddress : mac
        entry.lastConnectedAt = Date()
        entries.removeAll { $0.id == entry.id || $0.endpoint.caseInsensitiveCompare(address) == .orderedSame }
        entries.insert(entry, at: 0)
        while entries.count > 20 {
            let removed = entries.removeLast()
            deletePassword(for: removed.id)
        }
        setPassword(password, for: entry.id)
        persist()
    }

    func password(for entry: SavedConnection) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: entry.id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func remove(_ entry: SavedConnection) {
        entries.removeAll { $0.id == entry.id }
        deletePassword(for: entry.id)
        persist()
    }

    func removeAll() {
        entries.forEach { deletePassword(for: $0.id) }
        entries.removeAll()
        persist()
    }

    private func setPassword(_ password: String, for id: UUID) {
        deletePassword(for: id)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(password.utf8)
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    private func deletePassword(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
