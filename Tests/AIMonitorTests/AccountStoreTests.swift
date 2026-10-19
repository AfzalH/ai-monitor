import Foundation
import Testing
import MonitorCore
@testable import AIMonitor

@MainActor private final class MemoryVault: CredentialVault {
    var values: [UUID: Credential] = [:]
    func save(_ credential: Credential, id: UUID) { values[id] = credential }
    func read(_ id: UUID) throws -> Credential {
        guard let value = values[id] else { throw MonitorError.invalidPayload }; return value
    }
    func remove(_ id: UUID) { values[id] = nil }
}
private actor DelayedTransport: UsageTransport {
    var waiting: CheckedContinuation<Void, Never>?
    var started = false
    func get(_ request: URLRequest) async throws -> Data {
        if request.url!.path.hasSuffix("rate-limit-reset-credits") { throw MonitorError.invalidPayload }
        started = true
        await withCheckedContinuation { waiting = $0 }
        return Data(#"{"rate_limit":{"primary_window":{"used_percent":99,"limit_window_seconds":18000}}}"#.utf8)
    }
    func release() { waiting?.resume(); waiting = nil }
    func resetStarted() { started = false }
}
@Test @MainActor func reconnectCannotBeOverwrittenByOldRefresh() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = DelayedTransport()
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault())
    let account = Account(name: "First", provider: .codex)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "old"), snapshot: UsageSnapshot(plan: "Pro", windows: [QuotaWindow("Weekly", used: 70)]))
    let refresh = Task { await store.refresh() }
    while !(await transport.started) { await Task.yield() }
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "new"), snapshot: UsageSnapshot(plan: "Pro", windows: [QuotaWindow("Weekly", used: 3)]))
    await transport.release()
    await refresh.value
    #expect(store.snapshots[account.id]?.windows.first?.used == 3)
    #expect(store.errors[account.id] == nil)
}
@Test @MainActor func sameProviderAccountsPersistSeparatelyWithoutSecrets() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("accounts.json")
    let vault = MemoryVault()
    let store = AccountStore(file: file, vault: vault)
    let first = Account(name: "Original", provider: .codex)
    let second = Account(name: "Backup", provider: .codex)
    for account in [first, second] {
        try store.save(account: account, credential: Credential(kind: .bearer, secret: "secret-\(account.name)"), snapshot: UsageSnapshot(plan: "Pro", windows: [QuotaWindow("Weekly", used: 1)]))
    }
    let disk = try String(contentsOf: file, encoding: .utf8)
    #expect(!disk.contains("secret-"))
    let restored = AccountStore(file: file, vault: vault)
    #expect(restored.accounts.count == 2)
    restored.remove(first)
    #expect(restored.accounts == [second])
    #expect(vault.values[first.id] == nil)
    #expect(vault.values[second.id]?.secret == "secret-Backup")
}
@Test @MainActor func cancelledVerificationNeverSavesAccount() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = DelayedTransport()
    let vault = MemoryVault()
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: vault)
    let account = Account(name: "Cancelled", provider: .codex)
    let operation = Task { try await store.verifyAndSave(account: account, credential: Credential(kind: .bearer, secret: "fixture")) }
    while !(await transport.started) { await Task.yield() }
    operation.cancel()
    await transport.release()
    _ = try? await operation.value
    #expect(store.accounts.isEmpty)
    #expect(vault.values.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("accounts.json").path))
}

@Test @MainActor func renamePreservesConnectionAndUsage() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("accounts.json")
    let vault = MemoryVault()
    let store = AccountStore(file: file, vault: vault)
    let account = Account(name: "Original", provider: .codex)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Pro", windows: [QuotaWindow("Weekly", used: 7)]))
    try store.rename(account, to: "  Work  ")
    #expect(store.accounts.first?.name == "Work")
    #expect(store.accounts.first?.id == account.id)
    #expect(store.snapshots[account.id]?.windows.first?.used == 7)
    #expect(vault.values[account.id]?.secret == "fixture")
    #expect(AccountStore(file: file, vault: vault).accounts.first?.name == "Work")
    #expect(throws: MonitorError.self) { try store.rename(account, to: "  ") }
}

private actor CountingTransport: UsageTransport {
    var calls = 0
    var fail = false
    func get(_ request: URLRequest) async throws -> Data {
        calls += 1
        if fail { throw MonitorError.message("Rate limited") }
        return Data(#"{"five_hour":{"utilization":5}}"#.utf8)
    }
    func setFailure() { fail = true }
}

@Test @MainActor func refreshCooldownIncludesFailuresAndManualBypassesIt() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = CountingTransport()
    var now = Date(timeIntervalSince1970: 1000)
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), now: { now })
    let account = Account(name: "Claude", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    await store.refresh(onOpen: true)
    now = now.addingTimeInterval(59)
    await store.refresh(onOpen: true)
    #expect(await transport.calls == 1)
    await store.refresh()
    #expect(await transport.calls == 2)
    await transport.setFailure()
    now = now.addingTimeInterval(60)
    await store.refresh(onOpen: true)
    await store.refresh(onOpen: true)
    #expect(await transport.calls == 3)
    #expect(store.errors[account.id] != nil)
}

@Test @MainActor func accountOrderingSurvivesReloadWithoutChangingCredentials() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("accounts.json")
    let vault = MemoryVault()
    let store = AccountStore(file: file, vault: vault)
    let first = Account(name: "First", provider: .claude)
    let second = Account(name: "Second", provider: .codex)
    for account in [first, second] {
        try store.save(account: account, credential: Credential(kind: .bearer, secret: account.name), snapshot: UsageSnapshot(plan: "Plan", windows: []))
    }
    try store.moveAccount(second, by: -1)
    #expect(store.accounts == [second, first])
    #expect(AccountStore(file: file, vault: vault).accounts == [second, first])
    try store.moveAccount(second, by: -1)
    #expect(store.accounts == [second, first])
    #expect(vault.values[first.id]?.secret == "First")
    #expect(vault.values[second.id]?.secret == "Second")
}

import AppKit
import SwiftUI

@Test @MainActor func popoutShrinksForOneAccountAndCapsLongLists() async throws {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), vault: MemoryVault())
    func addAccount() throws {
        try store.save(account: Account(name: "Account", provider: .claude), credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: [QuotaWindow("5 hours", used: 3), QuotaWindow("Weekly", used: 7)]))
    }
    try addAccount()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defaults.set(40.0, forKey: "popoverHeightPercent")
    var measured: CGFloat = 0
    let view = DashboardView(screenHeight: 1000, heightChanged: { measured = $0 }).environmentObject(store).defaultAppStorage(defaults)
    let hosting = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 520, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.orderFront(nil)
    defer { window.close() }
    for _ in 0..<5 {
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(measured > 100 && measured < 400)
    for _ in 0..<5 { try addAccount() }
    for _ in 0..<5 {
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(measured == 400)
}

@Test @MainActor func nativeStatusItemOpensMeasuredPanelAndTogglesClosed() async throws {
    _ = NSApplication.shared
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("accounts.json")
    let store = AccountStore(file: file, vault: MemoryVault())
    store.showDemo()
    let controller = StatusBarController(store: store)
    defer { controller.shutdown() }
    controller.toggle()
    for _ in 0..<10 { try await Task.sleep(for: .milliseconds(30)) }
    let visible = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)) == "QuotaPanel" }
    #expect(visible.count == 1)
    if let panel = visible.first {
        #expect(panel.frame.height > 100)
        #expect(panel.frame.width == 520)
        controller.toggle()
        #expect(!panel.isVisible)
    }
}

@Test @MainActor func menuLabelUsesOnlyFirstAccountAndPreferencesPersist() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let file = dir.appendingPathComponent("accounts.json")
    let vault = MemoryVault()
    let store = AccountStore(file: file, vault: vault, defaults: defaults)
    let first = Account(name: "First", provider: .claude)
    let second = Account(name: "Second", provider: .claude)
    for (account, used) in [(first, 20.0), (second, 90.0)] {
        try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: [QuotaWindow("Weekly", used: used)]))
    }
    #expect(store.menuLabel == "80%")
    store.setMenuPrefix("", for: first)
    #expect(store.menuLabel == "80%")
    try store.moveAccount(second, by: -1)
    #expect(store.menuLabel == "80%")
    store.setMenuEnabled(first, false)
    #expect(store.menuLabel.isEmpty)
    let restored = AccountStore(file: file, vault: vault, defaults: defaults)
    #expect(!restored.isMenuEnabled(first))
    #expect(restored.menuPrefix(for: first).isEmpty)
}

@Test @MainActor func backgroundRefreshOnlyFetchesTopAccountAndStopsWhenDisabled() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = CountingTransport()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    var now = Date(timeIntervalSince1970: 1000)
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), now: { now }, defaults: defaults)
    let first = Account(name: "First", provider: .claude)
    let second = Account(name: "Second", provider: .claude)
    for account in [first, second] {
        try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: [QuotaWindow("Weekly", used: 50)]))
    }
    await store.refreshMenuAccounts()
    #expect(await transport.calls == 1)
    #expect(store.snapshots[first.id]?.windows.first?.used == 5)
    #expect(store.snapshots[second.id]?.windows.first?.used == 50)
    await store.refresh(onOpen: true)
    #expect(await transport.calls == 2) // Opening skips the top account already fetched.
    store.setMenuEnabled(store.accounts.first!, false)
    try store.moveAccount(second, by: -1)
    now = now.addingTimeInterval(60)
    await store.refreshMenuAccounts()
    #expect(await transport.calls == 2)
}

@Test @MainActor func schedulerFollowsTopAccountAndCanBeStopped() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = CountingTransport()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), defaults: defaults)
    let first = Account(name: "First", provider: .claude)
    let second = Account(name: "Second", provider: .claude)
    for account in [first, second] {
        try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    }
    store.setMenuEnabled(store.accounts.first!, false)
    let monitor = MenuBarRefreshScheduler(store: store, network: TestConnectivityMonitor())
    defer { monitor.stop() }
    try await Task.sleep(for: .milliseconds(80))
    #expect(await transport.calls == 0)
    store.setMenuEnabled(store.accounts.first!, true)
    for _ in 0..<50 where store.snapshots[first.id]?.windows.first?.used != 5 { try await Task.sleep(for: .milliseconds(10)) }
    let firstCalls = await transport.calls
    #expect(firstCalls == 1)
    try store.moveAccount(second, by: -1)
    store.setMenuEnabled(second, true)
    for _ in 0..<50 where store.snapshots[second.id]?.windows.first?.used != 5 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await transport.calls == 2)
    monitor.stop()
    store.setMenuEnabled(store.accounts.first!, false)
    store.setMenuEnabled(store.accounts.first!, true)
    try await Task.sleep(for: .milliseconds(80))
    #expect(await transport.calls == 2)
}

@Test @MainActor func disablingMenuMonitorCancelsPendingUpdateWithoutAccountError() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = DelayedTransport()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), defaults: defaults)
    let account = Account(name: "Top", provider: .codex)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Pro", windows: [QuotaWindow("Weekly", used: 7)]))
    let monitor = MenuBarRefreshScheduler(store: store, network: TestConnectivityMonitor())
    defer { monitor.stop() }
    while !(await transport.started) { await Task.yield() }
    store.setMenuEnabled(store.accounts.first!, false)
    // Let the published settings change cancel the scheduler before the
    // deliberately cancellation-insensitive transport returns its response.
    try await Task.sleep(for: .milliseconds(30))
    await transport.release()
    try await Task.sleep(for: .milliseconds(30))
    #expect(store.snapshots[account.id]?.windows.first?.used == 7)
    #expect(store.errors[account.id] == nil)
    #expect(store.menuLabel.isEmpty)
}

@Test @MainActor func cancelledTopRefreshCanRetryImmediately() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = DelayedTransport()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), defaults: defaults)
    let account = Account(name: "Top", provider: .codex)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Pro", windows: [QuotaWindow("Weekly", used: 7)]))
    let cancelled = Task { await store.refreshMenuAccounts() }
    while !(await transport.started) { await Task.yield() }
    cancelled.cancel()
    await transport.release()
    await cancelled.value
    #expect(store.nextMenuRefreshDelay == 1)
    await transport.resetStarted()
    let retry = Task { await store.refreshMenuAccounts() }
    for _ in 0..<50 where !(await transport.started) { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await transport.started)
    await transport.release()
    await retry.value
    #expect(store.snapshots[account.id]?.windows.first?.used == 99)
}

@Test @MainActor func backgroundDelayTracksLastActualAttempt() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = CountingTransport()
    var now = Date(timeIntervalSince1970: 1000)
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), now: { now }, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    try store.save(account: Account(name: "Top", provider: .claude), credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    await store.refreshMenuAccounts()
    now = now.addingTimeInterval(30)
    #expect(store.nextMenuRefreshDelay == 30)
    await store.refresh()
    now = now.addingTimeInterval(30)
    await store.refreshMenuAccounts()
    #expect(await transport.calls == 2)
    #expect(store.nextMenuRefreshDelay == 30)
}

private actor ProviderMenuTransport: UsageTransport {
    var accounts: [String] = []
    func get(_ request: URLRequest) async throws -> Data {
        if request.url!.path.hasSuffix("rate-limit-reset-credits") { throw MonitorError.invalidPayload }
        accounts.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        return Data(#"{"five_hour":{"utilization":20},"rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":604800}}}"#.utf8)
    }
}

@Test @MainActor func accountMenuSupportsMultipleAccountsOfSameProvider() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let file = dir.appendingPathComponent("accounts.json")
    let transport = ProviderMenuTransport()
    let vault = MemoryVault()
    let store = AccountStore(file: file, client: UsageClient(transport: transport), vault: vault, defaults: defaults)
    let first = Account(name: "Codex main", provider: .codex)
    let second = Account(name: "Codex backup", provider: .codex)
    let claude = Account(name: "Claude", provider: .claude)
    for (account, used) in [(first, 20.0), (second, 50.0), (claude, 10.0)] {
        try store.save(account: account, credential: Credential(kind: .bearer, secret: account.name), snapshot: UsageSnapshot(plan: "Plan", windows: [QuotaWindow("Weekly", used: used)]))
    }
    #expect(store.menuAccounts.map(\.id) == [first.id])
    store.setMenuEnabled(second, true)
    store.setMenuPrefix("x1", for: first)
    store.setMenuPrefix("x2", for: second)
    #expect(store.menuLabel == "x1 80% · x2 50%")
    await store.refreshMenuAccounts()
    #expect(await transport.accounts == ["Bearer Codex main", "Bearer Codex backup"])
    try store.moveAccount(second, by: -1)
    try store.rename(first, to: "Renamed")
    #expect(store.menuAccounts.map(\.id) == [second.id, first.id])
    let restored = AccountStore(file: file, vault: vault, defaults: defaults)
    #expect(restored.isMenuEnabled(first) && restored.isMenuEnabled(second))
    #expect(!restored.isMenuEnabled(claude))
    #expect(restored.menuPrefix(for: first) == "x1")
    #expect(restored.menuPrefix(for: second) == "x2")
    store.setMenuEnabled(first, false)
    store.setMenuEnabled(second, false)
    #expect(AccountStore(file: file, vault: vault, defaults: defaults).menuAccounts.isEmpty)
}

@Test @MainActor func providerPreferencesMigrateToPreviouslyDisplayedAccounts() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("accounts.json")
    let accounts = [Account(name: "First", provider: .codex), Account(name: "Backup", provider: .codex), Account(name: "Claude", provider: .claude)]
    try JSONEncoder().encode(accounts).write(to: file)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defaults.set(["codex": true, "claude": false], forKey: "menuProviderChoices")
    defaults.set(["codex": "Custom"], forKey: "menuProviderPrefixes")
    let store = AccountStore(file: file, vault: MemoryVault(), defaults: defaults)
    #expect(store.menuAccounts.map(\.id) == [accounts[0].id])
    #expect(store.menuPrefix(for: accounts[0]) == "Custom")
    store.setMenuEnabled(accounts[1], true)
    #expect(AccountStore(file: file, vault: MemoryVault(), defaults: defaults).menuAccounts.count == 2)
}

private actor RateLimitedTransport: UsageTransport {
    var calls = 0
    func get(_ request: URLRequest) async throws -> Data {
        calls += 1
        throw HTTPRateLimitError(retryAt: nil)
    }
}
@Test @MainActor func manualRefreshCannotBypassClaudeServerBackoff() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let transport = RateLimitedTransport()
    let client = UsageClient(transport: transport, claudeThrottle: ClaudeUsageThrottle(suiteName: suite))
    let vault = MemoryVault()
    let file = dir.appendingPathComponent("accounts.json")
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = AccountStore(file: file, client: client, vault: vault, defaults: defaults)
    let account = Account(name: "Claude", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: [QuotaWindow("Weekly", used: 20)]))
    await store.refresh()
    await store.refresh()
    await store.refreshMenuAccounts()
    #expect(await transport.calls == 1)
    #expect(store.snapshots[account.id]?.windows.first?.used == 20)
    #expect(store.errors[account.id]?.contains("Paused until") == true)
    #expect(store.nextMenuRefreshDelay > 800)
    let restored = AccountStore(file: file, client: UsageClient(transport: transport, claudeThrottle: ClaudeUsageThrottle(suiteName: suite)), vault: vault, defaults: defaults)
    await restored.refresh()
    #expect(await transport.calls == 1)
}

@Test @MainActor func offlineRefreshWaitsAndRetriesAllRequestedAccountsOnConnection() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = CountingTransport()
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    for name in ["First", "Second"] {
        try store.save(account: Account(name: name, provider: .claude), credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    }
    store.setNetworkAvailable(false)
    await store.refresh(onOpen: true)
    await store.refreshMenuAccounts()
    #expect(await transport.calls == 0)
    store.setNetworkAvailable(true)
    await store.refreshPendingAccounts()
    #expect(await transport.calls == 2)
    #expect(store.snapshots.values.allSatisfy { $0.windows.first?.used == 5 })
    await store.refreshPendingAccounts()
    #expect(await transport.calls == 2)
}

private actor RecoveringTransport: UsageTransport {
    var offline = true
    var calls = 0
    func get(_ request: URLRequest) async throws -> Data {
        calls += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return Data(#"{"five_hour":{"utilization":8}}"#.utf8)
    }
    func connect() { offline = false }
}
@Test @MainActor func connectionFailureRetriesNonMenuAccountWithoutWaitingForOpenCooldown() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = RecoveringTransport()
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let account = Account(name: "Not in menu", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    store.setMenuEnabled(account, false)
    await store.refresh(onOpen: true)
    #expect(store.errors[account.id] != nil)
    await store.refreshPendingAccounts()
    #expect(await transport.calls == 1)
    await transport.connect()
    store.setNetworkAvailable(false)
    store.setNetworkAvailable(true)
    await store.refreshPendingAccounts()
    #expect(store.errors[account.id] == nil)
    #expect(store.snapshots[account.id]?.windows.first?.used == 8)
    await store.refreshPendingAccounts()
    #expect(await transport.calls == 2)
}
@Test @MainActor func reconnectDoesNotBypassProviderBackoff() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = RateLimitedTransport()
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport, claudeThrottle: ClaudeUsageThrottle(suiteName: suite)), vault: MemoryVault(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let account = Account(name: "Claude", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    await store.refresh()
    store.setNetworkAvailable(false)
    await store.refresh()
    store.setNetworkAvailable(true)
    await store.refreshPendingAccounts()
    #expect(await transport.calls == 1)
    #expect(store.errors[account.id]?.contains("Paused until") == true)
}

@MainActor private final class TestConnectivityMonitor: ConnectivityMonitoring {
    var changed: (@Sendable (Bool) -> Void)?
    var connected = true
    func start(_ changed: @escaping @Sendable (Bool) -> Void) {
        self.changed = changed
        changed(connected)
    }
    func cancel() { changed = nil }
    func setConnected(_ connected: Bool) { self.connected = connected; changed?(connected) }
}

@Test @MainActor func schedulerWaitsForNetworkAndFetchesWhenItReturns() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = CountingTransport()
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let account = Account(name: "Startup", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    let network = TestConnectivityMonitor()
    network.connected = false
    let scheduler = MenuBarRefreshScheduler(store: store, network: network)
    defer { scheduler.stop() }
    await store.refresh()
    try await Task.sleep(for: .milliseconds(40))
    #expect(await transport.calls == 0)
    network.setConnected(true)
    for _ in 0..<100 where store.snapshots[account.id]?.windows.first?.used != 5 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.snapshots[account.id]?.windows.first?.used == 5)
    #expect(await transport.calls == 1)
    network.setConnected(false)
    network.setConnected(true)
    try await Task.sleep(for: .milliseconds(40))
    #expect(await transport.calls == 1)
}

private actor WaitingClaudeTransport: UsageTransport {
    var waiting: CheckedContinuation<Void, Never>?
    var calls = 0
    func get(_ request: URLRequest) async throws -> Data {
        calls += 1
        await withCheckedContinuation { waiting = $0 }
        try Task.checkCancellation()
        return Data(#"{"five_hour":{"utilization":8}}"#.utf8)
    }
    func release() { waiting?.resume(); waiting = nil }
}
@Test @MainActor func connectivityFlapDoesNotCancelRunningClaudeRequest() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let suite = UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let transport = WaitingClaudeTransport()
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport, claudeThrottle: ClaudeUsageThrottle(suiteName: suite)), vault: MemoryVault(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let account = Account(name: "Claude", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    let network = TestConnectivityMonitor()
    let scheduler = MenuBarRefreshScheduler(store: store, network: network)
    defer { scheduler.stop() }
    for _ in 0..<100 where await transport.calls == 0 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await transport.calls == 1)
    network.setConnected(false)
    try await Task.sleep(for: .milliseconds(40))
    network.setConnected(true)
    try await Task.sleep(for: .milliseconds(40))
    await transport.release()
    for _ in 0..<100 where store.snapshots[account.id]?.windows.first?.used != 8 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(store.snapshots[account.id]?.windows.first?.used == 8)
    #expect(store.errors[account.id] == nil)
    #expect(await transport.calls == 1)
}

private actor AuthenticationFailureTransport: UsageTransport {
    var fail = true
    func get(_ request: URLRequest) async throws -> Data {
        if fail { throw MonitorError.authenticationRequired("Sign-in expired. Reconnect this account.") }
        return Data(#"{"five_hour":{"utilization":8}}"#.utf8)
    }
    func recover() { fail = false }
}
@Test @MainActor func reconnectActionTracksAuthenticationFailureAndClearsAfterRecovery() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let transport = AuthenticationFailureTransport()
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: transport), vault: MemoryVault(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let account = Account(name: "Expired", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    await store.refresh()
    #expect(store.reconnectRequired.contains(account.id))
    await transport.recover()
    await store.refresh()
    #expect(!store.reconnectRequired.contains(account.id))
    #expect(store.errors[account.id] == nil)
}

@Test @MainActor func reconnectFromPopoverOpensSettingsForTheSelectedAccount() async throws {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = AccountStore(file: dir.appendingPathComponent("accounts.json"), client: UsageClient(transport: CountingTransport()), vault: MemoryVault(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let account = Account(name: "Second Claude", provider: .claude)
    try store.save(account: account, credential: Credential(kind: .bearer, secret: "fixture"), snapshot: UsageSnapshot(plan: "Max", windows: []))
    store.setMenuEnabled(account, false)
    let controller = StatusBarController(store: store)
    defer { controller.shutdown() }
    controller.reconnect(account)
    #expect(controller.settingsNavigation.reconnecting?.id == account.id)
    for _ in 0..<50 where !NSApp.windows.contains(where: { $0.title == "QuotaBar for AI Settings" && $0.attachedSheet != nil }) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(NSApp.windows.contains { $0.title == "QuotaBar for AI Settings" && $0.isVisible && $0.attachedSheet != nil })
}

@Test @MainActor func missingKeychainItemRequiresReconnect() throws {
    do {
        _ = try Keychain().read(UUID())
        Issue.record("Unexpected credential for a new account ID")
    } catch MonitorError.authenticationRequired { }
    catch { Issue.record("Missing credential did not offer reconnect: \(error.localizedDescription)") }
}
