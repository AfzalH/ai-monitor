import Foundation
import MonitorCore
import Security

/// Copies readable legacy credentials without deleting the original entries.
@MainActor final class MigratingCredentialVault: CredentialVault {
    let current: any CredentialVault
    let legacy: any CredentialVault
    private let defaults: UserDefaults?
    private var finished: Set<String>
    private let markerKey = "legacyCredentialMigrationFinished"

    init(current: any CredentialVault = Keychain(service: "com.srizon.quotabar.credentials"),
         legacy: any CredentialVault = Keychain(service: "com.local.ai-monitor.credentials"),
         defaults: UserDefaults? = .standard) {
        self.current = current
        self.legacy = legacy
        self.defaults = defaults
        self.finished = Set(defaults?.stringArray(forKey: "legacyCredentialMigrationFinished") ?? [])
    }

    private func markFinished(_ id: UUID) {
        if finished.insert(id.uuidString).inserted { defaults?.set(Array(finished), forKey: markerKey) }
    }

    func save(_ credential: Credential, id: UUID) throws {
        try current.save(credential, id: id)
        markFinished(id)
    }

    func read(_ id: UUID) throws -> Credential {
        do { let credential = try current.read(id); markFinished(id); return credential }
        catch CredentialLookupError.accessDenied {
            throw MonitorError.authenticationRequired("Keychain access was denied. Reconnect this account.")
        }
        catch CredentialLookupError.notFound {
            guard !finished.contains(id.uuidString) else {
                throw MonitorError.authenticationRequired("Credentials not found. Reconnect this account.")
            }
            let credential: Credential
            do { credential = try legacy.read(id) }
            catch CredentialLookupError.notFound {
                throw MonitorError.authenticationRequired("Credentials not found. Reconnect this account.")
            }
            catch CredentialLookupError.accessDenied {
                markFinished(id)
                throw MonitorError.authenticationRequired("Access to the old credential was denied. Reconnect this account.")
            }
            try save(credential, id: id)
            return credential
        }
    }

    func remove(_ id: UUID) throws {
        markFinished(id)
        var failures: [String] = []
        for (service, vault) in [("com.srizon.quotabar.credentials", current),
                                 ("com.local.ai-monitor.credentials", legacy)] {
            do { try vault.remove(id) }
            catch { failures.append("\(service): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { throw MonitorError.message(failures.joined(separator: "\n")) }
    }
}

enum CredentialLookupError: LocalizedError {
    case notFound, accessDenied
    var errorDescription: String? {
        switch self {
        case .notFound: "Credentials not found. Reconnect this account."
        case .accessDenied: "Keychain access was denied."
        }
    }
}

enum IdentityMigration {
    static let preferenceKeys = ["showRemaining", "popoverHeightPercent", "menuAccountChoices",
                                 "menuAccountPrefixes", "menuProviderChoices", "menuProviderPrefixes",
                                 "claudeUsageThrottle"]

    static func migratePreferences(from legacy: [String: Any], to defaults: UserDefaults) {
        guard !defaults.bool(forKey: "srizonIdentityMigrated") else { return }
        for key in preferenceKeys where defaults.object(forKey: key) == nil {
            if let value = legacy[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "srizonIdentityMigrated")
    }

    static func prepare() {
        #if !APP_STORE
        guard Bundle.main.bundleIdentifier == "com.srizon.quotabar" else { return }
        migratePreferences(from: UserDefaults.standard.persistentDomain(forName: "com.local.ai-monitor") ?? [:],
                           to: .standard)
        #endif
    }
}
