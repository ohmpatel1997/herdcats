import Foundation
import Security
import SwiftUI

/// Minimal Keychain wrapper for remembering connection secrets.
protocol KeychainOperations {
    func add(_ query: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

struct SystemKeychainOperations: KeychainOperations {
    func add(_ query: CFDictionary) -> OSStatus { SecItemAdd(query, nil) }
    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus { SecItemUpdate(query, attributes) }
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus { SecItemCopyMatching(query, result) }
    func delete(_ query: CFDictionary) -> OSStatus { SecItemDelete(query) }
}

enum KeychainStore {
    private static let service = "com.enchantinglabs.herdrcat"
    static let operations: KeychainOperations = SystemKeychainOperations()

    struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Could not access saved connection credentials (Keychain error \(status))." }
    }

    static func save(_ secret: String, account: String, using operations: KeychainOperations = KeychainStore.operations) throws {
        try save(Data(secret.utf8), account: account, using: operations)
    }

    static func save(_ data: Data, account: String, using operations: KeychainOperations = KeychainStore.operations) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        switch operations.add(addQuery as CFDictionary) {
        case errSecSuccess: return
        case errSecDuplicateItem:
            let status = operations.update(query as CFDictionary, [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ] as CFDictionary)
            if status == errSecSuccess { return }
            guard status == errSecItemNotFound else { throw StoreError(status: status) }
            // The item was deleted after duplicate detection. Retry the add once,
            // repairing an intervening insert with one final update.
            switch operations.add(addQuery as CFDictionary) {
            case errSecSuccess: return
            case errSecDuplicateItem:
                let retryStatus = operations.update(query as CFDictionary, [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                ] as CFDictionary)
                guard retryStatus == errSecSuccess else { throw StoreError(status: retryStatus) }
            case let retryStatus: throw StoreError(status: retryStatus)
            }
        case let status: throw StoreError(status: status)
        }
    }

    static func load(account: String, using operations: KeychainOperations = KeychainStore.operations, readOnly: Bool = false) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = operations.copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError(status: status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw StoreError(status: errSecDecode)
        }
        if readOnly { return secret }
        // Upgrade older saved credentials before exposing their value. The query
        // is scoped to this service and account, so unrelated Keychain items are
        // never touched. If the item disappeared or the policy change fails,
        // fail closed rather than returning data from storage we could not harden.
        let updateStatus = operations.update(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ] as CFDictionary,
            [kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary
        )
        guard updateStatus == errSecSuccess else { throw StoreError(status: updateStatus) }
        return secret
    }

    static func delete(account: String, using operations: KeychainOperations = KeychainStore.operations) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = operations.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError(status: status) }
    }

    // MARK: - Accounts

    enum Account {
        static let password = "connection.password"
        static let privateKey = "connection.privateKey"
    }
}

/// Non-secret connection settings. Credentials are isolated by profile in Keychain.
struct RecentConnection: Codable, Identifiable, Equatable {
    var id = UUID()
    var host: String
    var port: Int
    var username: String
    var authMode: String
    var remember: Bool
    var name: String?
    var lastConnectedAt: Date?
    var backend: ConnectionBackend = .tui

    enum CodingKeys: String, CodingKey {
        case id, host, port, username, authMode, remember, name, lastConnectedAt, backend
    }

    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "\(username)@\(host)" + (port == 22 ? "" : ":\(port)")
    }

    /// Compact label for tight spaces like the machine menu: the name, else the
    /// shortest unambiguous host label. Adds the username only when another
    /// saved login shares the host, and the full host only when abbreviations
    /// collide.
    func shortDisplayName(among connections: [RecentConnection]) -> String {
        let hasOtherBackend = connections.contains {
            $0.id != id && $0.host.lowercased() == host.lowercased()
                && $0.port == port && $0.username == username && $0.backend != backend
        }
        let suffix = hasOtherBackend ? " · \(backend.title)" : ""
        if let name = trimmedName { return name + suffix }
        let others = connections.filter { $0.id != id && $0.trimmedName == nil }
        for level in 0..<3 where !others.contains(where: {
            $0.hostLabel(level: level) == hostLabel(level: level) && (!hasOtherBackend || $0.backend == backend)
        }) {
            return hostLabel(level: level) + suffix
        }
        return hostLabel(level: 3) + suffix
    }

    private var trimmedName: String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    /// 0: short host · 1: user@short host · 2: full host · 3: user@full host.
    private func hostLabel(level: Int) -> String {
        let shownHost = level < 2 ? Self.abbreviatedHost(host) : host
        let user = level.isMultiple(of: 2) ? "" : "\(username)@"
        return user + shownHost + (port == 22 ? "" : ":\(port)")
    }

    /// Only abbreviate DNS names; keep numeric and IPv6 addresses intact.
    static func abbreviatedHost(_ host: String) -> String {
        if host.contains(":") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return host }
        return String(host.split(separator: ".").first ?? Substring(host))
    }

    var legacySecretAccount: String { "connection.\(id.uuidString).secret" }
    var secretAccount: String { credentialAccount(for: authMode) }
    var passphraseAccount: String { legacySecretAccount + ".passphrase" }

    func credentialAccount(for authMode: String) -> String {
        legacySecretAccount + (authMode == "privateKey" ? ".privateKey" : ".password")
    }

    /// Forget and disabling storage remove every authentication method, including old versions' slots.
    var credentialAccounts: [String] {
        [credentialAccount(for: "password"), credentialAccount(for: "privateKey"), passphraseAccount, legacySecretAccount]
    }

    func deleteCredentials(using keychain: KeychainOperations) throws {
        for account in credentialAccounts { try KeychainStore.delete(account: account, using: keychain) }
    }
}

extension RecentConnection {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        host = try values.decode(String.self, forKey: .host)
        port = try values.decode(Int.self, forKey: .port)
        username = try values.decode(String.self, forKey: .username)
        authMode = try values.decode(String.self, forKey: .authMode)
        remember = try values.decode(Bool.self, forKey: .remember)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        lastConnectedAt = try values.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        backend = try values.decodeIfPresent(ConnectionBackend.self, forKey: .backend) ?? .tui
    }
}

enum RecentConnectionStore {
    static let storageKey = "hc.recentConnections"

    // MARK: Servers
    // TUI and Herdr Core stay separate entries (own id and Keychain secret);
    // lists show them as one server.

    static func sameServer(_ lhs: RecentConnection, _ rhs: RecentConnection) -> Bool {
        lhs.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == rhs.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            && lhs.port == rhs.port && lhs.username == rhs.username
    }

    /// Every saved runtime of `server`, in list order.
    static func runtimes(of server: RecentConnection, in entries: [RecentConnection]) -> [RecentConnection] {
        entries.filter { sameServer($0, server) }
    }

    /// One entry per saved runtime of `server`, TUI first; duplicates show the one used last.
    static func savedRuntimes(of server: RecentConnection, in entries: [RecentConnection]) -> [RecentConnection] {
        let group = runtimes(of: server, in: entries)
        return ConnectionBackend.allCases.compactMap { backend in
            group.filter { $0.backend == backend }
                .max { ($0.lastConnectedAt ?? .distantPast) < ($1.lastConnectedAt ?? .distantPast) }
        }
    }

    /// One entry per server, at its first position: the runtime used last.
    static func servers(_ entries: [RecentConnection]) -> [RecentConnection] {
        var result: [RecentConnection] = []
        for entry in entries where !result.contains(where: { sameServer($0, entry) }) {
            let group = runtimes(of: entry, in: entries)
            result.append(group.max { ($0.lastConnectedAt ?? .distantPast) < ($1.lastConnectedAt ?? .distantPast) } ?? entry)
        }
        return result
    }

    /// "TUI", "Herdr Core", or both for a server with each runtime saved.
    static func runtimeSummary(of server: RecentConnection, in entries: [RecentConnection]) -> String {
        let saved = Set(runtimes(of: server, in: entries).map(\.backend))
        return ConnectionBackend.allCases.filter(saved.contains).map(\.title).joined(separator: " + ")
    }

    /// A server has one name across its runtimes.
    static func renameServer(_ server: RecentConnection, to name: String?, defaults: UserDefaults = .standard,
                             using keychain: KeychainOperations = KeychainStore.operations) throws {
        var entries = try load(defaults: defaults, using: keychain)
        for index in entries.indices where sameServer(entries[index], server) { entries[index].name = name }
        try persist(entries, defaults: defaults)
    }

    /// Forgets every runtime of a server.
    @discardableResult
    static func removeServer(
        _ server: RecentConnection, defaults: UserDefaults = .standard,
        using keychain: KeychainOperations = KeychainStore.operations
    ) throws -> [RecentConnection] {
        var updated = try load(defaults: defaults, using: keychain)
        for entry in runtimes(of: server, in: updated) {
            updated = try remove(entry, defaults: defaults, using: keychain)
        }
        return updated
    }
    private static let pendingMigrationKey = "hc.pendingCredentialMigration"

    private struct PendingMigration: Codable {
        let sourceAccount: String
        let entry: RecentConnection
        let destinationAccount: String

        init(sourceAccount: String, entry: RecentConnection) {
            self.sourceAccount = sourceAccount
            self.entry = entry
            destinationAccount = entry.secretAccount
        }

        private enum CodingKeys: String, CodingKey { case sourceAccount, entry, destinationAccount }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            sourceAccount = try values.decode(String.self, forKey: .sourceAccount)
            entry = try values.decode(RecentConnection.self, forKey: .entry)
            // A journal must resume against the account used when its copy was created.
            destinationAccount = try values.decodeIfPresent(String.self, forKey: .destinationAccount) ?? entry.legacySecretAccount
        }
    }

    static func config(
        for entry: RecentConnection,
        using keychain: KeychainOperations = KeychainStore.operations
    ) -> ConnectionConfig? {
        guard let value = try? ConnectionSignIn.load(entry, using: keychain), value.isReady,
              !value.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.config
    }

    static func snapshot(defaults: UserDefaults = .standard) -> [RecentConnection] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([RecentConnection].self, from: data)) ?? []
    }

    static func load(defaults: UserDefaults = .standard, using keychain: KeychainOperations = KeychainStore.operations) throws -> [RecentConnection] {
        try finishPendingMigration(defaults: defaults, using: keychain)
        if let data = defaults.data(forKey: storageKey) {
            return (try? JSONDecoder().decode([RecentConnection].self, from: data)) ?? []
        }

        // Preserve the single connection saved by earlier versions of the app.
        let host = (defaults.string(forKey: "hc.host") ?? "").trimmingCharacters(in: .whitespaces)
        let username = (defaults.string(forKey: "hc.username") ?? "").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !username.isEmpty else { return [] }
        let port = Int(defaults.string(forKey: "hc.port") ?? "22") ?? 22
        guard (1...65_535).contains(port) else { return [] }
        let entry = RecentConnection(
            host: host, port: port, username: username,
            authMode: defaults.string(forKey: "hc.authMode") ?? "password",
            remember: defaults.object(forKey: "hc.remember") as? Bool ?? true
        )
        if entry.remember {
            let account = entry.authMode == "privateKey"
                ? KeychainStore.Account.privateKey : KeychainStore.Account.password
            if let secret = try KeychainStore.load(account: account, using: keychain) {
                // A pending marker makes cleanup retryable if the app stops between
                // recording the profile and deleting the verified legacy item.
                let pending = PendingMigration(sourceAccount: account, entry: entry)
                let pendingData = try JSONEncoder().encode(pending)
                defaults.set(pendingData, forKey: pendingMigrationKey)
                guard defaults.data(forKey: pendingMigrationKey) == pendingData else { throw StoreError.metadataWriteFailed }
                try KeychainStore.save(secret, account: entry.secretAccount, using: keychain)
                guard try KeychainStore.load(account: entry.secretAccount, using: keychain) == secret else {
                    throw KeychainStore.StoreError(status: errSecDecode)
                }
                // Migration preserves the pending profile exactly; it is not a new connection.
                try persist([entry], defaults: defaults)
                try finishPendingMigration(defaults: defaults, using: keychain)
                return [entry]
            }
        }
        try persist([entry], defaults: defaults)
        return [entry]
    }

    static func entry(
        host: String, port: Int, username: String, authMode: String,
        remember: Bool, name: String? = nil, backend: ConnectionBackend = .tui, in entries: [RecentConnection]
    ) -> RecentConnection {
        let host = host.trimmingCharacters(in: .whitespaces)
        let username = username.trimmingCharacters(in: .whitespaces)
        var entry = entries.first {
            $0.host.lowercased() == host.lowercased() && $0.port == port && $0.username == username
                && $0.backend == backend
        } ?? RecentConnection(host: host, port: port, username: username, authMode: authMode, remember: remember, backend: backend)
        entry.authMode = authMode
        entry.remember = remember
        if let name { entry.name = name }
        return entry
    }

    @discardableResult
    static func record(
        _ entry: RecentConnection, in entries: [RecentConnection], defaults: UserDefaults = .standard,
        now: Date = .now, stampConnected: Bool = true, updateName: Bool = true,
        using keychain: KeychainOperations = KeychainStore.operations
    ) throws -> [RecentConnection] {
        var entry = entry
        var updated = entries
        let isDuplicate = { (other: RecentConnection) in sameServer(other, entry) && other.backend == entry.backend }
        // A server keeps one entry per runtime: this one takes the slot of any duplicate.
        let slot: Int
        var removedEntries: [RecentConnection] = []
        if let index = updated.firstIndex(where: { $0.id == entry.id }) ?? updated.firstIndex(where: isDuplicate) {
            if updated[index].id != entry.id { removedEntries.append(updated[index]) }
            entry.lastConnectedAt = stampConnected ? now : updated[index].lastConnectedAt
            if !updateName { entry.name = updated[index].name }
            updated[index] = entry
            slot = index
        } else {
            entry.lastConnectedAt = stampConnected ? now : nil
            updated.append(entry)
            slot = updated.count - 1
        }
        let removed = updated.indices.filter { $0 != slot && isDuplicate(updated[$0]) }
        removedEntries += removed.map { updated[$0] }
        updated = updated.indices.filter { !removed.contains($0) }.map { updated[$0] }
        try persist(updated, defaults: defaults)
        for duplicate in removedEntries where duplicate.id != entry.id {
            try duplicate.deleteCredentials(using: keychain)
        }
        return updated
    }

    static func move(
        fromOffsets: IndexSet, toOffset: Int, defaults: UserDefaults = .standard,
        using keychain: KeychainOperations = KeychainStore.operations
    ) throws -> [RecentConnection] {
        var entries = try load(defaults: defaults, using: keychain)
        entries.move(fromOffsets: fromOffsets, toOffset: toOffset)
        try persist(entries, defaults: defaults)
        return entries
    }

    /// Pure editing state. Only Save reaches storage or Keychain; discarding this
    /// value (including swipe dismissal) has no side effects.
    struct ManagementDraft {
        private(set) var connections: [RecentConnection]
        private let originalIDs: Set<UUID>
        private var renamedIDs: Set<UUID> = []

        init(connections: [RecentConnection]) {
            self.connections = connections
            originalIDs = Set(connections.map(\.id))
        }

        /// Rows are servers; each edit applies to all of a server's runtimes.
        var servers: [RecentConnection] { RecentConnectionStore.servers(connections) }

        mutating func rename(id: UUID, to name: String) {
            guard let server = connections.first(where: { $0.id == id }) else { return }
            for index in connections.indices where RecentConnectionStore.sameServer(connections[index], server) {
                connections[index].name = name
                renamedIDs.insert(connections[index].id)
            }
        }

        mutating func move(fromOffsets: IndexSet, toOffset: Int) {
            var order = servers
            order.move(fromOffsets: fromOffsets, toOffset: toOffset)
            connections = order.flatMap { RecentConnectionStore.runtimes(of: $0, in: connections) }
        }

        mutating func delete(at offsets: IndexSet) {
            let removed = offsets.map { servers[$0] }
            connections.removeAll { entry in removed.contains { RecentConnectionStore.sameServer($0, entry) } }
        }

        @discardableResult
        func save(defaults: UserDefaults = .standard,
                  using keychain: KeychainOperations = KeychainStore.operations) throws -> [RecentConnection] {
            let current = try RecentConnectionStore.load(defaults: defaults, using: keychain)
            let deletedIDs = originalIDs.subtracting(connections.map(\.id))
            // Merge only explicit name changes and order into fresh records. Never
            // restore a removed profile or overwrite newer destination/auth/recency.
            var updated = connections.compactMap { draft -> RecentConnection? in
                guard var latest = current.first(where: { $0.id == draft.id }) else { return nil }
                if renamedIDs.contains(draft.id) { latest.name = draft.name }
                return latest
            }
            updated += current.filter { !originalIDs.contains($0.id) }
            // Match Forget's fail-closed deletion order: a failure keeps metadata
            // visible and the draft open for retry. Surviving secrets are untouched.
            for entry in current where deletedIDs.contains(entry.id) {
                try entry.deleteCredentials(using: keychain)
            }
            try RecentConnectionStore.persist(updated, defaults: defaults)
            return updated
        }
    }

    /// Records that a saved connection must no longer remember credentials, in place.
    /// Never inserts an unsaved connection and never reorders the list.
    @discardableResult
    static func disableRemembering(
        _ entry: RecentConnection, defaults: UserDefaults = .standard,
        using keychain: KeychainOperations = KeychainStore.operations
    ) throws -> [RecentConnection] {
        var entries = try load(defaults: defaults, using: keychain)
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return entries }
        var updated = entries[index]
        updated.remember = false
        guard entries[index] != updated else { return entries }
        entries[index] = updated
        try persist(entries, defaults: defaults)
        return entries
    }

    /// Forgets a saved connection: deletes its Keychain secret and passphrase first
    /// (so a Keychain failure leaves the entry visible and retryable), then removes
    /// it from the saved list.
    @discardableResult
    static func remove(
        _ entry: RecentConnection, defaults: UserDefaults = .standard,
        using keychain: KeychainOperations = KeychainStore.operations
    ) throws -> [RecentConnection] {
        try entry.deleteCredentials(using: keychain)
        let updated = try load(defaults: defaults, using: keychain).filter { $0.id != entry.id }
        try persist(updated, defaults: defaults)
        return updated
    }

    private static func persist(_ entries: [RecentConnection], defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(entries)
        defaults.set(data, forKey: storageKey)
        guard defaults.data(forKey: storageKey) == data else {
            throw StoreError.metadataWriteFailed
        }
    }

    private static func finishPendingMigration(defaults: UserDefaults, using keychain: KeychainOperations) throws {
        guard let data = defaults.data(forKey: pendingMigrationKey) else { return }
        let pending = try JSONDecoder().decode(PendingMigration.self, from: data)
        let entries: [RecentConnection]
        if let current = defaults.data(forKey: storageKey) {
            guard let decoded = try? JSONDecoder().decode([RecentConnection].self, from: current) else {
                throw StoreError.metadataWriteFailed
            }
            entries = decoded
        } else {
            entries = []
        }
        let committedEntry = entries.first { $0.id == pending.entry.id }
        let hasCommittedProfile = committedEntry == pending.entry && pending.entry.remember
        if defaults.data(forKey: storageKey) != nil && committedEntry == nil {
            // The profile was removed or replaced after the migration began.
            // Do not recreate it or clean up the legacy credential.
            defaults.removeObject(forKey: pendingMigrationKey)
            return
        }
        if committedEntry != nil && !hasCommittedProfile {
            // Settings changed after the interrupted migration; never replay its
            // pending copy or cleanup against the edited profile.
            defaults.removeObject(forKey: pendingMigrationKey)
            return
        }
        guard let source = try KeychainStore.load(account: pending.sourceAccount, using: keychain) else {
            guard hasCommittedProfile else { throw KeychainStore.StoreError(status: errSecItemNotFound) }
            // The committed profile proves migration already finished; this is a
            // crash after source deletion but before clearing the pending marker.
            defaults.removeObject(forKey: pendingMigrationKey)
            return
        }
        var destination = try KeychainStore.load(account: pending.destinationAccount, using: keychain)
        if destination == nil && hasCommittedProfile {
            // The profile was already committed and its credential was later removed.
            // Leave the legacy item intact; replay must not silently restore it.
            defaults.removeObject(forKey: pendingMigrationKey)
            return
        }
        if destination == nil {
            try KeychainStore.save(source, account: pending.destinationAccount, using: keychain)
            destination = try KeychainStore.load(account: pending.destinationAccount, using: keychain)
        }
        guard destination == source else {
            guard hasCommittedProfile else { throw KeychainStore.StoreError(status: errSecDuplicateItem) }
            // The destination may have been edited since migration; do not overwrite it
            // or delete the legacy source based on stale migration intent.
            defaults.removeObject(forKey: pendingMigrationKey)
            return
        }
        if !hasCommittedProfile {
            let entries = try defaults.data(forKey: storageKey).map { try JSONDecoder().decode([RecentConnection].self, from: $0) } ?? []
            try persist(entries + [pending.entry], defaults: defaults)
        }
        try KeychainStore.delete(account: pending.sourceAccount, using: keychain)
        defaults.removeObject(forKey: pendingMigrationKey)
    }

    struct StoreError: LocalizedError {
        static let metadataWriteFailed = StoreError()
        var errorDescription: String? { "Could not save connection settings. Please try again." }
    }
}

/// Host public keys are trust anchors, kept separately from login credentials.
/// A failed Keychain read must never turn a known host into a first-use prompt.
actor SSHHostKeyStore {
    static let shared: SSHHostKeyStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-connectionReadyUITest"),
           let run = ProcessInfo.processInfo.environment["HC_CONNECTION_READY_RUN"], UUID(uuidString: run) != nil {
            return SSHHostKeyStore(service: "com.enchantinglabs.herdrcat.ui-test-host-keys.\(run)")
        }
        #endif
        return SSHHostKeyStore()
    }()
    private let service: String

    init(service: String = "com.enchantinglabs.herdrcat.ssh-host-keys") {
        self.service = service
    }

    #if DEBUG
    func removeUITestPin(host: String, port: Int) throws {
        guard service.hasPrefix("com.enchantinglabs.herdrcat.ui-test-host-keys.") else { return }
        let status = SecItemDelete(query(host: host, port: port) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError(status: status) }
    }
    #endif

    static func account(host: String, port: Int) -> String {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "[\(host)]:\(port)"
    }

    private func query(host: String, port: Int) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account(host: host, port: port)]
    }

    func load(host: String, port: Int) throws -> String? {
        var query = query(host: host, port: port)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError(status: status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw StoreError(status: errSecDecode)
        }
        // Opportunistically upgrade pins stored under a weaker accessibility class.
        // Best effort: the pin is already read, and a failed upgrade must never turn
        // a known host into an unknown one.
        _ = SecItemUpdate(
            self.query(host: host, port: port) as CFDictionary,
            [kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary
        )
        return key
    }

    /// First-use approval is insert-only: it cannot replace an existing pin.
    func trust(_ key: String, host: String, port: Int) throws {
        var query = query(host: host, port: port)
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard try load(host: host, port: port) == key else {
                throw StoreError(status: errSecDuplicateItem)
            }
        } else if status != errSecSuccess {
            throw StoreError(status: status)
        }
    }

    /// Replace only the pin reviewed by the user. A stale review must fail closed.
    func replace(_ key: String, replacing previousKey: String, host: String, port: Int) throws {
        guard try load(host: host, port: port) == previousKey else {
            throw StoreError(status: errSecDuplicateItem)
        }
        let match = query(host: host, port: port)
        let status = SecItemUpdate(match as CFDictionary,
                                  [kSecValueData as String: Data(key.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary)
        guard status == errSecSuccess else { throw StoreError(status: status) }
    }

    struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Could not access saved SSH host keys (Keychain error \(status)). Connection stopped."
        }
    }
}

/// Credential decisions shared by saved-card sign-in and connection setup.
struct ConnectionSignIn: Identifiable {
    var entry: RecentConnection
    var secret = ""
    var passphrase = ""
    var savePassphrase = false
    /// Auto: connect detects the runtime; `entry.backend` is a placeholder until then.
    var detectsBackend = false
    /// nil leaves the inactive credential untouched. A supplied value edits it,
    /// subject to settings' credential ownership and explicit edit intent below.
    var otherSecret: String?
    /// Settings values belong to one runtime. Only deliberate edits may clear or
    /// replace another saved runtime's inactive fields or storage preferences.
    struct CredentialEdits {
        let ownerID: UUID
        var password = false
        var privateKey = false
        var passphrase = false
        var remember = false
        /// The key loaded alongside the phrase, before any key edits.
        var passphraseKey: String?

        func secret(for mode: String) -> Bool { mode == "privateKey" ? privateKey : password }
    }
    var credentialEdits: CredentialEdits?
    var id: UUID { entry.id }
    var isKey: Bool { entry.authMode == "privateKey" }
    var encrypted: Bool { isKey && (try? OpenSSHEd25519.isEncrypted(pem: secret)) == true }
    var needsSecret: Bool {
        if !isKey { return secret.isEmpty }
        guard !secret.isEmpty else { return true }
        do {
            if try !OpenSSHEd25519.isEncrypted(pem: secret) {
                _ = try OpenSSHEd25519.parseRawPrivateKey(pem: secret)
            }
            _ = try OpenSSHEd25519.parsePublicKey(pem: secret)
            return false
        } catch { return true }
    }
    var needsPassphrase: Bool { encrypted && passphrase.isEmpty }
    var isReady: Bool { !needsSecret && !needsPassphrase }
    var config: ConnectionConfig {
        ConnectionConfig(host: entry.host, port: entry.port, username: entry.username,
            auth: isKey ? .privateKey(secret, passphrase: encrypted ? passphrase : nil) : .password(secret),
            backend: entry.backend, detectsBackend: detectsBackend)
    }

    static func importPrivateKey(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw OpenSSHKeyError.invalidFormat("The private key file must contain UTF-8 or ASCII text.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Older profiles used one slot whose type was defined by their saved auth mode.
    /// Keep that interpretation while copying to a mode-specific slot; never infer it from edited settings.
    private static func loadSecret(_ entry: RecentConnection, using keychain: KeychainOperations, readOnly: Bool) throws -> String {
        var secret = try KeychainStore.load(account: entry.secretAccount, using: keychain, readOnly: readOnly)
        if let legacy = try KeychainStore.load(account: entry.legacySecretAccount, using: keychain, readOnly: readOnly) {
            if readOnly { return secret ?? legacy }
            if secret == nil {
                try KeychainStore.save(legacy, account: entry.secretAccount, using: keychain)
                secret = try KeychainStore.load(account: entry.secretAccount, using: keychain)
                guard secret == legacy else { throw KeychainStore.StoreError(status: errSecDecode) }
            }
            // A different canonical value may be a newer edit. Prefer it and leave the source until an explicit save.
            if secret == legacy { try KeychainStore.delete(account: entry.legacySecretAccount, using: keychain) }
        }
        return secret ?? ""
    }

    /// Saved-card sign-ins edit only the selected method. Settings explicitly opt into editing inactive fields too.
    static func load(_ entry: RecentConnection, using keychain: KeychainOperations = KeychainStore.operations,
                     readOnly: Bool = false, includingInactiveCredentials: Bool = false) throws -> Self {
        guard entry.remember else { return Self(entry: entry) }
        let secret = try loadSecret(entry, using: keychain, readOnly: readOnly)
        var other: String?
        if includingInactiveCredentials {
            let otherMode = entry.authMode == "privateKey" ? "password" : "privateKey"
            other = try KeychainStore.load(account: entry.credentialAccount(for: otherMode), using: keychain, readOnly: readOnly) ?? ""
        }
        let phrase: String
        if entry.authMode == "privateKey" || includingInactiveCredentials {
            phrase = try KeychainStore.load(account: entry.passphraseAccount, using: keychain, readOnly: readOnly) ?? ""
        } else {
            phrase = ""
        }
        return Self(entry: entry, secret: secret, passphrase: phrase, savePassphrase: !phrase.isEmpty, otherSecret: other)
    }

    private func preservingStoragePreference(in entries: [RecentConnection]) -> RecentConnection {
        var destination = entry
        if let credentialEdits, credentialEdits.ownerID != entry.id, !credentialEdits.remember,
           let saved = entries.first(where: { $0.id == entry.id }) {
            destination.remember = saved.remember
        }
        return destination
    }

    private static func samePrivateKeyData(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return lhs == rhs }
        if lhs == rhs { return true }
        func container(_ pem: String) -> Data? {
            let lines = pem.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard lines.first == "-----BEGIN OPENSSH PRIVATE KEY-----",
                  lines.last == "-----END OPENSSH PRIVATE KEY-----" else { return nil }
            return Data(base64Encoded: lines.dropFirst().dropLast().joined())
        }
        guard let left = container(lhs), let right = container(rhs) else { return false }
        return left == right
    }

    /// Explicit saves may clear credentials; failed connection attempts never save replacements.
    func persist(defaults: UserDefaults = .standard, using keychain: KeychainOperations = KeychainStore.operations,
                 connected: Bool = true, updateName: Bool = false) throws {
        let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        let entry = preservingStoragePreference(in: entries)
        let ownsCredentials = credentialEdits == nil || credentialEdits?.ownerID == entry.id
            || !entries.contains(where: { $0.id == entry.id })
        if entry.remember {
            if let previous = entries.first(where: { $0.id == entry.id }) {
                _ = try Self.loadSecret(previous, using: keychain, readOnly: false)
            }
            let writesSelectedSecret = !secret.isEmpty || ownsCredentials || credentialEdits?.secret(for: entry.authMode) == true
            let otherMode = isKey ? "password" : "privateKey"
            let writesOtherSecret = otherSecret != nil && (ownsCredentials || credentialEdits?.secret(for: otherMode) == true)
            let writtenKey: String? = isKey ? (writesSelectedSecret ? secret : nil) : (writesOtherSecret ? otherSecret : nil)
            var previousKey: String?
            if writtenKey != nil {
                previousKey = try KeychainStore.load(account: entry.credentialAccount(for: "privateKey"), using: keychain)
            }
            let keyEncryption: Bool? = writtenKey.flatMap { key in
                let normalized = key.split(whereSeparator: \.isNewline).joined(separator: "\n")
                guard (try? OpenSSHEd25519.parsePublicKey(pem: normalized)) != nil,
                      let encrypted = try? OpenSSHEd25519.isEncrypted(pem: normalized) else { return nil }
                if !encrypted && (try? OpenSSHEd25519.parseRawPrivateKey(pem: normalized)) == nil { return nil }
                return encrypted
            }
            let replacedKey = keyEncryption != nil && !Self.samePrivateKeyData(writtenKey, previousKey)
            let plaintextKey = keyEncryption == false
            // Keep unfinished drafts intact; a recognized replacement must have
            // its own phrase or an explicit phrase edit before saving that phrase.
            let associatedPassphrase = credentialEdits == nil || credentialEdits?.passphrase == true
                || keyEncryption == nil || Self.samePrivateKeyData(writtenKey, credentialEdits?.passphraseKey)
            // Retire the ambiguous slot before explicit clearing, so it can never restore a removed value.
            try KeychainStore.delete(account: entry.legacySecretAccount, using: keychain)
            // A working selected credential can refresh every runtime. An empty
            // field from a different runtime cannot silently erase its sign-in.
            if !secret.isEmpty { try KeychainStore.save(secret, account: entry.secretAccount, using: keychain) }
            else if writesSelectedSecret {
                try KeychainStore.delete(account: entry.secretAccount, using: keychain)
            }
            if let otherSecret, writesOtherSecret {
                let account = entry.credentialAccount(for: otherMode)
                if otherSecret.isEmpty { try KeychainStore.delete(account: account, using: keychain) }
                else { try KeychainStore.save(otherSecret, account: account, using: keychain) }
            }
            // The passphrase belongs to the private key even while Password is selected.
            let clearedKey = credentialEdits?.privateKey == true && (isKey ? secret.isEmpty : otherSecret == "")
            let editsPassphrase = ownsCredentials || credentialEdits?.passphrase == true || clearedKey
                || (isKey && !secret.isEmpty && !encrypted)
                || (isKey && savePassphrase && !passphrase.isEmpty)
            let updatesPassphrase = (editsPassphrase && associatedPassphrase) || replacedKey || plaintextKey || clearedKey
            if updatesPassphrase && (isKey || otherSecret != nil || savePassphrase || !passphrase.isEmpty) {
                // Removing the key removes its persisted phrase even when the
                // form retains a passphrase draft for further editing.
                if !clearedKey && !plaintextKey && associatedPassphrase && savePassphrase && !passphrase.isEmpty {
                    try KeychainStore.save(passphrase, account: entry.passphraseAccount, using: keychain)
                } else {
                    try KeychainStore.delete(account: entry.passphraseAccount, using: keychain)
                }
            }
        } else {
            try entry.deleteCredentials(using: keychain)
        }
        _ = try RecentConnectionStore.record(entry,
            in: RecentConnectionStore.load(defaults: defaults, using: keychain), defaults: defaults,
            stampConnected: connected, updateName: updateName, using: keychain)
    }

    /// The saved entry for the runtime Auto connected with. An entry already
    /// saved for another runtime is never repointed; a new one is added instead.
    func resolving(_ backend: ConnectionBackend, in entries: [RecentConnection]) -> Self {
        guard entry.backend != backend else { return self }
        var value = self
        // Match by server, not sign-in method, so a new auth mode refreshes the saved runtime.
        let saved = entries.first { RecentConnectionStore.sameServer($0, entry) && $0.backend == backend }
        value.entry = saved ?? (entries.contains { $0.id == entry.id }
            ? RecentConnection(host: entry.host, port: entry.port, username: entry.username,
                authMode: entry.authMode, remember: entry.remember, backend: backend)
            : entry)
        value.entry.authMode = entry.authMode
        value.entry.remember = entry.remember
        value.entry.name = entry.name
        value.entry.backend = backend
        return value
    }

    /// After an Auto connect: saves the runtime used and, when the machine has
    /// both, adds the other runtime with the same sign-in unless it is saved already.
    func persistDetected(backend: ConnectionBackend, found: Set<ConnectionBackend>,
                         defaults: UserDefaults = .standard, using keychain: KeychainOperations = KeychainStore.operations,
                         connected: Bool = true, updateName: Bool = false) throws {
        let value = resolving(backend, in: try RecentConnectionStore.load(defaults: defaults, using: keychain))
        try value.persist(defaults: defaults, using: keychain, connected: connected, updateName: updateName)
        guard let other = ConnectionBackend.allCases.first(where: { $0 != backend }), found.contains(other) else { return }
        // Same SSH account, so the sign-in that just worked is the sibling's too.
        try value.persistSibling(other, defaults: defaults, using: keychain)
    }

    /// Auto edits a whole server: this entry and every other runtime saved for
    /// `original` move to this destination and sign-in, keeping ids and history.
    func persistServer(from original: RecentConnection, defaults: UserDefaults = .standard,
                       using keychain: KeychainOperations = KeychainStore.operations, updateName: Bool) throws {
        let others = RecentConnectionStore.runtimes(of: original, in: try RecentConnectionStore.load(defaults: defaults, using: keychain))
            .filter { $0.id != entry.id }
        try persist(defaults: defaults, using: keychain, connected: false, updateName: updateName)
        for runtime in others {
            var moved = self
            moved.entry.id = runtime.id
            moved.entry.backend = runtime.backend
            moved.entry.lastConnectedAt = runtime.lastConnectedAt
            try moved.persist(defaults: defaults, using: keychain, connected: false, updateName: updateName)
        }
    }

    /// Saves this sign-in as the server's `backend` runtime, reusing its entry when saved.
    func persistSibling(_ backend: ConnectionBackend, defaults: UserDefaults = .standard,
                        using keychain: KeychainOperations = KeychainStore.operations) throws {
        let entries = try RecentConnectionStore.load(defaults: defaults, using: keychain)
        let saved = entries.first { RecentConnectionStore.sameServer($0, entry) && $0.backend == backend }
        var sibling = self
        sibling.entry = RecentConnection(id: saved?.id ?? UUID(), host: entry.host, port: entry.port, username: entry.username,
            authMode: entry.authMode, remember: entry.remember, name: entry.name,
            lastConnectedAt: saved?.lastConnectedAt, backend: backend)
        try sibling.persist(defaults: defaults, using: keychain, connected: false, updateName: true)
    }

    func prepareAttempt(defaults: UserDefaults = .standard, using keychain: KeychainOperations = KeychainStore.operations) throws {
        if !entry.remember {
            var entry = entry
            if let credentialEdits, credentialEdits.ownerID != entry.id, !credentialEdits.remember {
                entry = try preservingStoragePreference(in: RecentConnectionStore.load(defaults: defaults, using: keychain))
            }
            guard !entry.remember else { return }
            try entry.deleteCredentials(using: keychain)
            try RecentConnectionStore.disableRemembering(entry, defaults: defaults, using: keychain)
        }
    }
}
