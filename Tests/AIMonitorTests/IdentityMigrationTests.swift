import Foundation
import Testing
import MonitorCore
@testable import AIMonitor

@MainActor private final class MigrationVault: CredentialVault {
    var values: [UUID: Credential] = [:]
    var readError: Error?
    var saveError: Error?
    var removalError: Error?
    var reads = 0
    var removals = 0
    func read(_ id: UUID) throws -> Credential {
        reads += 1
        if let readError { throw readError }
        guard let value = values[id] else { throw CredentialLookupError.notFound }
        return value
    }
    func save(_ credential: Credential, id: UUID) throws {
        if let saveError { throw saveError }
        values[id] = credential
    }
    func remove(_ id: UUID) throws {
        removals += 1
        if let removalError { throw removalError }
        values[id] = nil
    }
}

@Test @MainActor func legacyCredentialCopiesOnceWithoutDeletingOriginal() throws {
    let current = MigrationVault(), legacy = MigrationVault(), id = UUID()
    legacy.values[id] = Credential(kind: .bearer, secret: "legacy")
    let vault = MigratingCredentialVault(current: current, legacy: legacy, defaults: nil)
    #expect(try vault.read(id).secret == "legacy")
    #expect(current.values[id]?.secret == "legacy")
    #expect(legacy.values[id]?.secret == "legacy")
    current.values[id] = Credential(kind: .bearer, secret: "new")
    #expect(try vault.read(id).secret == "new")
    #expect(legacy.reads == 1)
}

@Test @MainActor func migrationDoesNotFallBackWhenCurrentKeychainIsLocked() throws {
    let current = MigrationVault(), legacy = MigrationVault()
    current.readError = MonitorError.message("locked")
    let vault = MigratingCredentialVault(current: current, legacy: legacy, defaults: nil)
    #expect(throws: (any Error).self) { try vault.read(UUID()) }
    #expect(legacy.reads == 0)
}

@Test @MainActor func failedMigrationPreservesLegacyCredentialForRetry() throws {
    let current = MigrationVault(), legacy = MigrationVault(), id = UUID()
    legacy.values[id] = Credential(kind: .bearer, secret: "legacy")
    current.saveError = MonitorError.message("denied")
    let vault = MigratingCredentialVault(current: current, legacy: legacy, defaults: nil)
    #expect(throws: (any Error).self) { try vault.read(id) }
    #expect(legacy.values[id]?.secret == "legacy")
    current.saveError = nil
    #expect(try vault.read(id).secret == "legacy")
}

@Test @MainActor func removalAttemptsBothServicesAndIdentifiesFailedCleanup() throws {
    let current = MigrationVault(), legacy = MigrationVault(), id = UUID()
    current.removalError = MonitorError.message("denied")
    let vault = MigratingCredentialVault(current: current, legacy: legacy, defaults: nil)
    do { try vault.remove(id); Issue.record("Expected cleanup failure") }
    catch { #expect(error.localizedDescription.contains("com.srizon.quotabar.credentials")) }
    #expect(current.removals == 1)
    #expect(legacy.removals == 1)
}

@Test func preferencesMigrateOnceWithoutOverwritingNewChoicesOrCopyingOtherKeys() {
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "showRemaining")
    IdentityMigration.migratePreferences(from: ["showRemaining": true, "popoverHeightPercent": 80.0,
                                                "claudeUsageThrottle": Data([1, 2]), "unrelated": "no"], to: defaults)
    #expect(!defaults.bool(forKey: "showRemaining"))
    #expect(defaults.double(forKey: "popoverHeightPercent") == 80)
    #expect(defaults.data(forKey: "claudeUsageThrottle") == Data([1, 2]))
    #expect(defaults.object(forKey: "unrelated") == nil)
    defaults.removeObject(forKey: "popoverHeightPercent")
    IdentityMigration.migratePreferences(from: ["popoverHeightPercent": 80.0], to: defaults)
    #expect(defaults.object(forKey: "popoverHeightPercent") == nil)
}

@Test @MainActor func deniedLegacyReadIsNotRepeatedAndReconnectRecovers() throws {
    let current = MigrationVault(), legacy = MigrationVault(), id = UUID()
    let suite = UUID().uuidString, defaults: UserDefaults
    defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    legacy.readError = CredentialLookupError.accessDenied
    let vault = MigratingCredentialVault(current: current, legacy: legacy, defaults: defaults)
    for _ in 0..<2 {
        do { _ = try vault.read(id); Issue.record("Expected reconnect") }
        catch { guard case .authenticationRequired = error as? MonitorError else { Issue.record("Expected authentication error"); return } }
    }
    let restarted = MigratingCredentialVault(current: current, legacy: legacy, defaults: defaults)
    #expect(throws: (any Error).self) { try restarted.read(id) }
    #expect(legacy.reads == 1)
    try restarted.save(Credential(kind: .bearer, secret: "new"), id: id)
    #expect(try restarted.read(id).secret == "new")
    current.values[id] = nil
    #expect(throws: (any Error).self) { try restarted.read(id) }
    #expect(legacy.reads == 1)
}
