import Foundation
import Combine
import Network

@MainActor protocol ConnectivityMonitoring {
    func start(_ changed: @escaping @Sendable (Bool) -> Void)
    func cancel()
}

@MainActor final class SystemConnectivityMonitor: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    func start(_ changed: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in changed(path.status != .unsatisfied) }
        monitor.start(queue: DispatchQueue(label: "QuotaBar.connectivity"))
    }
    func cancel() { monitor.cancel() }
}

/// Exists only for the running status item, never for previews or data stores.
@MainActor final class MenuBarRefreshScheduler {
    private let store: AccountStore
    private var subscription: AnyCancellable?
    private var task: Task<Void, Never>?
    private var monitoredIDs: [UUID] = []
    private var selectedIDs: [UUID] = []
    private var connected = false
    private var stopped = false
    private let network: any ConnectivityMonitoring

    init(store: AccountStore, network: any ConnectivityMonitoring = SystemConnectivityMonitor()) {
        self.network = network
        self.store = store
        store.setNetworkAvailable(false)
        network.start { [weak self] available in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                guard available != self.connected else { return }
                self.connected = available
                self.store.setNetworkAvailable(available)
                // A path change must not cancel a request already waiting for
                // connectivity. Its transport owns completion and timeout.
                if available, self.task == nil || !self.store.hasRequestsInFlight {
                    self.configure(force: true)
                }
            }
        }
        subscription = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.configure() }
        }
        configure()
    }
    private func configure(force: Bool = false) {
        guard !stopped else { return }
        let ids = store.demo ? [] : store.accounts.map(\.id)
        let selection = store.menuAccounts.map(\.id)
        guard force || ids != monitoredIDs || selection != selectedIDs else { return }
        task?.cancel()
        task = nil
        monitoredIDs = ids
        selectedIDs = selection
        guard !ids.isEmpty, connected else { return }
        task = Task { [weak store] in
            while !Task.isCancelled {
                guard let store, !store.demo, store.accounts.map(\.id) == ids else { return }
                await store.refreshPendingAccounts()
                guard !Task.isCancelled, store.menuAccounts.map(\.id) == selection else { return }
                await store.refreshMenuAccounts()
                do { try await Task.sleep(for: .seconds(min(60, store.nextMenuRefreshDelay))) }
                catch { return }
            }
        }
    }
    func stop() {
        stopped = true
        network.cancel()
        task?.cancel()
        task = nil
        subscription = nil
        monitoredIDs = []
    }
}
