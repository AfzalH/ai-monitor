import Foundation
import Combine

/// Exists only for the running status item, never for previews or data stores.
@MainActor final class MenuBarRefreshScheduler {
    private let store: AccountStore
    private var subscription: AnyCancellable?
    private var task: Task<Void, Never>?
    private var monitoredIDs: [UUID] = []
    private var stopped = false

    init(store: AccountStore) {
        self.store = store
        subscription = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.configure() }
        }
        configure()
    }
    private func configure() {
        guard !stopped else { return }
        let ids = store.demo ? [] : store.menuAccounts.map(\.id)
        guard ids != monitoredIDs else { return }
        task?.cancel()
        task = nil
        monitoredIDs = ids
        guard !ids.isEmpty else { return }
        task = Task { [weak store] in
            while !Task.isCancelled {
                guard let store, !store.demo, store.menuAccounts.map(\.id) == ids else { return }
                await store.refreshMenuAccounts()
                do { try await Task.sleep(for: .seconds(store.nextMenuRefreshDelay)) }
                catch { return }
            }
        }
    }
    func stop() {
        stopped = true
        task?.cancel()
        task = nil
        subscription = nil
        monitoredIDs = []
    }
}
