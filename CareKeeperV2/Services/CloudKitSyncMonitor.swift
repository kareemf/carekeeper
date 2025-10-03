import SwiftUI
import Network
import CloudKit

@MainActor
@Observable
class CloudKitSyncMonitor {
    enum SyncStatus {
        case idle
        case offline
        case checking
        case accountIssue

        var displayMessage: String {
            switch self {
            case .idle:
                return NSLocalizedString("iCloud", comment: "Sync status: idle")
            case .offline:
                return NSLocalizedString("Offline", comment: "Sync status: offline")
            case .checking:
                return NSLocalizedString("Checking...", comment: "Sync status: checking")
            case .accountIssue:
                return NSLocalizedString("iCloud issue", comment: "Sync status: account issue")
            }
        }

        var systemImage: String {
            switch self {
            case .idle:
                return "icloud"
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

    private init() {
        setupNetworkMonitoring()
        checkCloudKitStatus()
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                if path.status == .satisfied {
                    if case .offline = self.status {
                        self.status = .idle
                        self.checkCloudKitStatus()
                    }
                } else {
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
                let container = CKContainer(identifier: "iCloud.com.kareemf.CareKeeperCK")
                let accountStatus = try await container.accountStatus()

                await MainActor.run {
                    switch accountStatus {
                    case .available:
                        self.status = .idle
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
