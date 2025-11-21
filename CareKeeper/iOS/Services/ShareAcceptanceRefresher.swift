import Foundation

@MainActor
protocol SharedCareeRefreshable: AnyObject {
    var sharedCarees: [Caree] { get }
    func fetchSharedCarees() async
}

@MainActor
protocol CacheRefreshing: AnyObject {
    func invalidateAndRefresh() async throws
}

extension CloudKitSharedRecordsService: SharedCareeRefreshable {}
extension LocalCacheService: CacheRefreshing {}

/// Listens for CloudKit share acceptance and proactively refreshes the shared caree list with backoff.
@MainActor
final class ShareAcceptanceRefresher {
    private let sharedRecordsService: SharedCareeRefreshable
    private weak var cacheService: CacheRefreshing?
    private let notificationCenter: NotificationCenter
    private let retryDelays: [TimeInterval]
    private var observer: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private let logger = AppLogger.sharing

    init(
        sharedRecordsService: SharedCareeRefreshable,
        cacheService: CacheRefreshing?,
        notificationCenter: NotificationCenter = .default,
        retryDelays: [TimeInterval] = [1, 2, 3]
    ) {
        self.sharedRecordsService = sharedRecordsService
        self.cacheService = cacheService
        self.notificationCenter = notificationCenter
        self.retryDelays = retryDelays

        observer = notificationCenter.addObserver(
            forName: .cloudKitShareAccepted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleShareAcceptance()
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        refreshTask?.cancel()
    }

    private func handleShareAcceptance() {
        logger.info("🔔 Share accepted; scheduling shared caree refresh with backoff.")
        refreshTask?.cancel()

        let baselineIDs = Set(sharedRecordsService.sharedCarees.map(\.id))
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await performRefresh(baselineIDs: baselineIDs)
        }
    }

    private func performRefresh(baselineIDs: Set<UUID>) async {
        for (attemptIndex, delay) in retryDelays.enumerated() {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                logger.debug("Share acceptance refresh cancelled before attempt \(attemptIndex + 1)")
                return
            }

            logger.info("⏳ Refreshing shared carees after acceptance (attempt \(attemptIndex + 1))")
            await sharedRecordsService.fetchSharedCarees()

            do {
                try await cacheService?.invalidateAndRefresh()
            } catch {
                logger.warning("⚠️ Failed to refresh cache after share acceptance: \(error.localizedDescription)")
            }

            let currentIDs = Set(sharedRecordsService.sharedCarees.map(\.id))
            let newIDs = currentIDs.subtracting(baselineIDs)

            if !newIDs.isEmpty {
                logger.info("✅ Share acceptance refresh completed with \(newIDs.count) new caree(s) found.")
                return
            }

            if attemptIndex == retryDelays.count - 1 {
                logger.info("ℹ️ Share acceptance refresh finished without new carees; data may still be propagating.")
            }
        }
    }
}
