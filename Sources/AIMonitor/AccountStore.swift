import Foundation
import Security
import SwiftUI
import MonitorCore

@MainActor protocol CredentialVault {
    func save(_ credential: Credential, id: UUID) throws
    func read(_ id: UUID) throws -> Credential
    func remove(_ id: UUID) throws
}
struct Keychain: CredentialVault {
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.local.ai-monitor.credentials",
         kSecAttrAccount as String: id.uuidString]
    }
    func save(_ credential: Credential, id: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    func read(_ id: UUID) throws -> Credential {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw MonitorError.authenticationRequired("Credentials not found. Reconnect this account.") }
        try check(status)
        guard let data = result as? Data else { throw MonitorError.authenticationRequired("Credentials not found. Reconnect this account.") }
        return try JSONDecoder().decode(Credential.self, from: data)
    }
    func remove(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw MonitorError.message("Keychain access failed, code \(status). Unlock your Mac and try again.") }
    }
}

@MainActor final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var snapshots: [UUID: UsageSnapshot] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var refreshing = false
    @Published private(set) var reconnectRequired: Set<UUID> = []
    @Published var storageError: String?
    @Published var demo = false
    @Published private var menuAccountChoices: [String: Bool]?
    @Published private var menuAccountPrefixes: [String: String]
    private let defaults: UserDefaults
    private var accountAttempts: [UUID: Date] = [:]
    private var inFlight: Set<UUID> = []
    private var deferredUntil: [UUID: Date] = [:]
    let client: UsageClient
    private let vault: any CredentialVault
    private var revisions: [UUID: UUID] = [:]
    private var lastRefreshAttempt: Date?
    private var networkAvailable = true
    private var pendingNetworkRefresh: Set<UUID> = []
    private var networkRetryAfter: [UUID: Date] = [:]

    private let now: () -> Date
    private let file: URL
    init(file: URL? = nil, client: UsageClient = UsageClient(), vault: any CredentialVault = Keychain(), now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard) {
        self.client = client; self.vault = vault; self.now = now
        self.defaults = defaults
        menuAccountChoices = defaults.dictionary(forKey: "menuAccountChoices") as? [String: Bool]
        menuAccountPrefixes = defaults.dictionary(forKey: "menuAccountPrefixes") as? [String: String] ?? [:]
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI Monitor/accounts.json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do { accounts = try JSONDecoder().decode([Account].self, from: Data(contentsOf: self.file)) }
            catch { storageError = "Could not load saved accounts. \(error.localizedDescription)" }
        }
        if menuAccountChoices == nil, !accounts.isEmpty {
            let legacy = defaults.dictionary(forKey: "menuProviderChoices") as? [String: Bool]
            let prefixes = defaults.dictionary(forKey: "menuProviderPrefixes") as? [String: String] ?? [:]
            var seen: Set<Provider> = []
            var choices: [String: Bool] = [:]
            for account in accounts {
                let first = seen.insert(account.provider).inserted
                choices[account.id.uuidString] = legacy.map { first && ($0[account.provider.rawValue] ?? false) } ?? (account.id == accounts.first?.id)
                if first, let prefix = prefixes[account.provider.rawValue] { menuAccountPrefixes[account.id.uuidString] = prefix }
            }
            menuAccountChoices = choices
            defaults.set(choices, forKey: "menuAccountChoices")
            defaults.set(menuAccountPrefixes, forKey: "menuAccountPrefixes")
        }
    }
    var hasRequestsInFlight: Bool { !inFlight.isEmpty }

    func setNetworkAvailable(_ available: Bool) {
        if available && !networkAvailable { networkRetryAfter.removeAll() }
        networkAvailable = available
    }
    func refreshPendingAccounts() async {
        guard networkAvailable, !demo else { return }
        for account in accounts where pendingNetworkRefresh.contains(account.id) {
            guard !Task.isCancelled else { return }
            await refreshAccount(account, respectCooldown: true)
        }
    }
    private func persist(_ accounts: [Account]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(accounts).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func save(account: Account, credential: Credential, snapshot: UsageSnapshot) throws {
        guard !demo else { return }
        try vault.save(credential, id: account.id)
        var updated = accounts
        if let index = updated.firstIndex(where: { $0.id == account.id }) { updated[index] = account }
        else { updated.append(account) }
        try persist(updated)
        revisions[account.id] = UUID()
        accounts = updated; snapshots[account.id] = snapshot; errors[account.id] = nil
        reconnectRequired.remove(account.id)
        if menuAccountChoices == nil { setMenuEnabled(account, true) }
    }
    func verifyAndSave(account: Account, credential: Credential) async throws {
        let snapshot = try await client.fetch(provider: account.provider, credential: credential, accountID: account.id)
        try Task.checkCancellation()
        try save(account: account, credential: credential, snapshot: snapshot)
    }
    func rename(_ account: Account, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !demo, !name.isEmpty, let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw MonitorError.message("Enter an account name.")
        }
        var updated = accounts
        updated[index].name = name
        try persist(updated)
        accounts = updated
    }
    func remove(_ account: Account) {
        do {
            let updated = accounts.filter { $0.id != account.id }
            try vault.remove(account.id)
            try persist(updated)
            accounts = updated; snapshots[account.id] = nil; errors[account.id] = nil
            reconnectRequired.remove(account.id)
        } catch { storageError = error.localizedDescription }
    }
    func moveAccount(_ account: Account, by offset: Int) throws {
        guard !demo, let source = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let target = source + offset
        guard accounts.indices.contains(target) else { return }
        var updated = accounts
        updated.swapAt(source, target)
        try persist(updated)
        accounts = updated
    }
    func refresh(onOpen: Bool = false) async {
        guard !refreshing, !demo, !accounts.isEmpty else { return }
        guard networkAvailable else {
            pendingNetworkRefresh.formUnion(accounts.map(\.id))
            for account in accounts where errors[account.id] == nil { errors[account.id] = "Waiting for a network connection. Usage will refresh automatically." }
            return
        }
        let date = now()
        if onOpen, let lastRefreshAttempt, date.timeIntervalSince(lastRefreshAttempt) < 60 { return }
        // Failed attempts also consume the cooldown, so opening cannot hammer a
        // provider that is rate limiting us. Manual refresh always bypasses it.
        lastRefreshAttempt = date
        refreshing = true
        defer { refreshing = false }
        for account in accounts { await refreshAccount(account, respectCooldown: onOpen) }
    }
    func isMenuEnabled(_ account: Account) -> Bool {
        menuAccountChoices?[account.id.uuidString] ?? (menuAccountChoices == nil && accounts.first?.id == account.id)
    }
    func setMenuEnabled(_ account: Account, _ enabled: Bool) {
        var choices = menuAccountChoices ?? Dictionary(uniqueKeysWithValues: accounts.map { ($0.id.uuidString, isMenuEnabled($0)) })
        choices[account.id.uuidString] = enabled
        menuAccountChoices = choices
        defaults.set(choices, forKey: "menuAccountChoices")
    }
    func menuPrefix(for account: Account) -> String {
        menuAccountPrefixes[account.id.uuidString] ?? ""
    }
    func setMenuPrefix(_ prefix: String, for account: Account) {
        menuAccountPrefixes[account.id.uuidString] = prefix
        defaults.set(menuAccountPrefixes, forKey: "menuAccountPrefixes")
    }
    var menuAccounts: [Account] { accounts.filter { isMenuEnabled($0) } }
    func refreshMenuAccounts() async {
        guard networkAvailable, !refreshing, !demo else { return }
        for account in menuAccounts {
            guard !Task.isCancelled else { return }
            await refreshAccount(account, respectCooldown: true)
        }
    }
    var nextMenuRefreshDelay: TimeInterval {
        menuAccounts.map { account -> TimeInterval in
            if !networkAvailable { return 60 }
            if let retry = networkRetryAfter[account.id], retry > now() { return retry.timeIntervalSince(now()) }
            if refreshing || inFlight.contains(account.id) { return 1 }
            if let until = deferredUntil[account.id], until > now() { return until.timeIntervalSince(now()) }
            guard let attempt = accountAttempts[account.id] else { return 1 }
            return min(60, max(1, 60 - now().timeIntervalSince(attempt)))
        }.min() ?? 60
    }
    private func refreshAccount(_ account: Account, respectCooldown: Bool) async {
        guard networkAvailable else {
            pendingNetworkRefresh.insert(account.id)
            return
        }
        guard !inFlight.contains(account.id) else { return }
        let date = now()
        if let retry = networkRetryAfter[account.id], retry > date { return }
        if let until = deferredUntil[account.id], until > date { return }
        if respectCooldown, let attempted = accountAttempts[account.id], date.timeIntervalSince(attempted) < 60 { return }
        let previousAttempt = accountAttempts[account.id]
        accountAttempts[account.id] = date
        inFlight.insert(account.id)
        defer {
            if Task.isCancelled { accountAttempts[account.id] = previousAttempt }
            inFlight.remove(account.id)
        }
        let revision = revisions[account.id]
        do {
            let credential = try vault.read(account.id)
            let result = try await client.fetch(provider: account.provider, credential: credential, accountID: account.id)
            try Task.checkCancellation()
            guard revisions[account.id] == revision, accounts.contains(where: { $0.id == account.id }), !demo else { return }
            snapshots[account.id] = result; errors[account.id] = nil
            reconnectRequired.remove(account.id)
            deferredUntil[account.id] = nil
            pendingNetworkRefresh.remove(account.id)
            networkRetryAfter[account.id] = nil
        } catch let deferred as UsageRefreshDeferred {
            guard revisions[account.id] == revision, accounts.contains(where: { $0.id == account.id }), !demo else { return }
            deferredUntil[account.id] = deferred.until
            if deferred.rateLimited || snapshots[account.id] == nil { errors[account.id] = deferred.localizedDescription }
        } catch let limited as HTTPRateLimitError {
            guard revisions[account.id] == revision, accounts.contains(where: { $0.id == account.id }), !demo else { return }
            let until = max(now().addingTimeInterval(60), limited.retryAt ?? now())
            deferredUntil[account.id] = until
            errors[account.id] = "Usage checks paused until " + until.formatted(date: .omitted, time: .shortened) + "."
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut].contains(error.code) {
            guard !Task.isCancelled, revisions[account.id] == revision, accounts.contains(where: { $0.id == account.id }), !demo else { return }
            pendingNetworkRefresh.insert(account.id)
            networkRetryAfter[account.id] = now().addingTimeInterval(60)
            if error.code == .notConnectedToInternet { accountAttempts[account.id] = previousAttempt }
            errors[account.id] = "Connection unavailable. Usage will retry automatically."
        } catch is CancellationError {
            // Disabling the background monitor is not an account error.
        } catch {
            if !Task.isCancelled, revisions[account.id] == revision, accounts.contains(where: { $0.id == account.id }), !demo {
                pendingNetworkRefresh.remove(account.id)
                if case .authenticationRequired = error as? MonitorError {
                    reconnectRequired.insert(account.id)
                } else { reconnectRequired.remove(account.id) }
                errors[account.id] = error.localizedDescription
            }
        }
    }
    var menuLabel: String {
        menuAccounts.map { account in
            let prefix = menuPrefix(for: account).trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String
            if demo { value = "Demo" }
            else if errors[account.id] != nil { value = "!" }
            else if let remaining = snapshots[account.id]?.windows.map(\.remaining).min() { value = "\(Int(remaining))%" }
            else { value = "--" }
            return prefix.isEmpty ? value : prefix + " " + value
        }.joined(separator: " · ")
    }
    func showDemo() {
        guard accounts.isEmpty else { return }
        demo = true
        let examples: [(Provider, String, String, [Double])] = [(.claude, "Personal Claude", "Max", [32, 61]), (.codex, "Original Codex", "Pro", [18, 1]), (.codex, "Backup Codex", "Plus", [4, 5]), (.opencode, "Personal OpenCode", "Go", [22, 47, 63])]
        for (provider, name, plan, values) in examples {
            let account = Account(name: name, provider: provider)
            accounts.append(account)
            let labels = ["5 hours", "Weekly", "Monthly"]
            let windows = values.enumerated().map { QuotaWindow(labels[$0.offset], used: $0.element, resetsAt: Date().addingTimeInterval([7500.0, 590400, 1209600][$0.offset])) }
            var snapshot = UsageSnapshot(plan: plan, windows: windows)
            if provider == .codex {
                snapshot.resets = try? UsageParser.resets(Data(#"{"available_count":2,"credits":[{"status":"available","expires_at":"2026-11-01T00:00:00Z"},{"status":"available","expires_at":"2026-11-09T00:00:00Z"}]}"#.utf8))
            }
            snapshots[account.id] = snapshot
        }
    }
    func leaveDemo() { demo = false; accounts = []; snapshots = [:]; errors = [:] }
}
