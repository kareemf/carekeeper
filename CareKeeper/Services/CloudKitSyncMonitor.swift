import SwiftUI
import Network
import CloudKit
import Combine

@MainActor
@Observable
class CloudKitSyncMonitor {
    enum SyncStatus {
        case idle
        case syncing
        case offline
        case checking
        case accountIssue

        var displayMessage: String {
            switch self {
            case .idle:
                return NSLocalizedString("Synced", comment: "Sync status: idle")
            case .syncing:
                return NSLocalizedString("Syncing...", comment: "Sync status: syncing")
            case .offline:
                return NSLocalizedString("Offline", comment: "Sync status: offline")
            case .checking:
                return NSLocalizedString("Checking...", comment: "Sync status: checking")
            case .accountIssue:
                return NSLocalizedString("Syncing Issue", comment: "Sync status: account issue")
            }
        }

        var systemImage: String {
            switch self {
            case .idle:
                return "icloud"
            case .syncing:
                return "arrow.triangle.2.circlepath"
            case .offline:
                return "wifi.slash"
            case .checking:
                return "icloud.and.arrow.up.and.arrow.down"
            case .accountIssue:
                return "exclamationmark.icloud"
            }
        }

        var color: Color {
            switch self {
            case .idle:
                return .secondary
            case .syncing:
                return .blue
            case .offline:
                return .orange
            case .checking:
                return .blue
            case .accountIssue:
                return .red
            }
        }

        var isTappable: Bool {
            switch self {
            case .offline, .accountIssue:
                return true
            default:
                return false
            }
        }
    }

    static let shared = CloudKitSyncMonitor()

    private(set) var status: SyncStatus = .idle
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.carekeeper.networkmonitor")
    private var cancellables = Set<AnyCancellable>()

    // Service references (set externally)
    private weak var cloudKitService: CloudKitDataService?
    private weak var sharedRecordsService: CloudKitSharedRecordsService?
    private weak var cacheService: LocalCacheService?

    private init() {
        setupNetworkMonitoring()
        // Don't check CloudKit status immediately - wait for services to be configured
        // and for actual sync attempts, which will reveal real connectivity issues
    }

    /// Configure services to monitor for sync status
    func configureServices(
        cloudKitService: CloudKitDataService,
        sharedRecordsService: CloudKitSharedRecordsService,
        cacheService: LocalCacheService
    ) {
        self.cloudKitService = cloudKitService
        self.sharedRecordsService = sharedRecordsService
        self.cacheService = cacheService

        // Observe CloudKitDataService.syncStatus
        cloudKitService.$syncStatus
            .sink { [weak self] syncStatus in
                Task { @MainActor in
                    self?.updateStatus()
                }
            }
            .store(in: &cancellables)

        // Observe CloudKitSharedRecordsService.isLoading
        sharedRecordsService.$isLoading
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatus()
                }
            }
            .store(in: &cancellables)

        // Observe LocalCacheService.isLoading
        cacheService.$isLoading
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatus()
                }
            }
            .store(in: &cancellables)
    }

    /// Update status based on priority: offline > syncing > idle
    /// Note: accountIssue is only shown during explicit CloudKit status check,
    /// and is immediately cleared once any sync activity occurs
    private func updateStatus() {
        // Priority 1: Network issues
        let monitor = NWPathMonitor()
        if monitor.currentPath.status != .satisfied {
            AppLogger.cloudkit.debug("🔄 SyncMonitor: Setting status to .offline (network not satisfied)")
            status = .offline
            return
        }

        // Priority 2: Active syncing (check if any service is actively working)
        let isCloudKitSyncing: Bool = {
            if case .syncing = cloudKitService?.syncStatus {
                return true
            }
            return false
        }()
        let isSharedRecordsLoading = sharedRecordsService?.isLoading ?? false
        let isCacheLoading = cacheService?.isLoading ?? false

        AppLogger.cloudkit.debug("🔄 SyncMonitor: updateStatus - CloudKit: \(isCloudKitSyncing), SharedRecords: \(isSharedRecordsLoading), Cache: \(isCacheLoading), Current: \(String(describing: self.status))")

        if isCloudKitSyncing || isSharedRecordsLoading || isCacheLoading {
            AppLogger.cloudkit.debug("🔄 SyncMonitor: Setting status to .syncing")
            status = .syncing
            return
        }

        // Priority 3: Default to idle
        // Don't persist accountIssue - if we reach here, services are idle and working fine
        AppLogger.cloudkit.debug("🔄 SyncMonitor: Setting status to .idle")
        status = .idle
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                if path.status == .satisfied {
                    // When network comes back, just update status based on service activity
                    // Don't automatically check CloudKit account (causes false accountIssue in simulator)
                    AppLogger.cloudkit.debug("🔄 SyncMonitor: Network online, updating status")
                    self.updateStatus()
                } else {
                    AppLogger.cloudkit.debug("🔄 SyncMonitor: Network offline")
                    self.status = .offline
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func checkCloudKitStatus() {
        status = .checking

        Task {
            do {
                let container = CKContainer(identifier: CloudKitConfig.containerID)
                let accountStatus = try await container.accountStatus()

                await MainActor.run {
                    switch accountStatus {
                    case .available:
                        self.updateStatus()
                    case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
                        self.status = .accountIssue
                    @unknown default:
                        self.status = .accountIssue
                    }
                }
            } catch {
                await MainActor.run {
                    self.status = .accountIssue
                }
            }
        }
    }

    func retry() {
        checkCloudKitStatus()
    }

    deinit {
        monitor.cancel()
    }
}
