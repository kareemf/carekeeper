#if os(iOS)
import SwiftUI
import SwiftData
import CloudKit

struct CareeShareButton: View {
    let caree: Caree
    let isSynced: Bool

    @Environment(\.modelContext) private var modelContext

    @State private var showingShareSheet = false
    @State private var share: CKShare?
    @State private var error: Error?
    @State private var isLoading = false
    @State private var showingSyncAlert = false

    private let sharingService = CloudKitSharingService()
    private let container = CKContainer(identifier: CloudKitConfig.containerID)

    var body: some View {
        Button {
            // Pre-share validation
            if !isSynced {
                showingSyncAlert = true
            } else {
                Task {
                    await prepareShare()
                }
            }
        } label: {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: sharingService.isShared(caree, in: modelContext)
                      ? "person.crop.circle.badge.checkmark"
                      : "square.and.arrow.up")
            }
        }
        .disabled(isLoading)
        .alert(
            NSLocalizedString("Not Synced to iCloud", comment: "Sync alert title"),
            isPresented: $showingSyncAlert
        ) {
            Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("This caree hasn't synced to iCloud yet. Please wait a moment or pull down to refresh, then try again.", comment: "Sync alert message"))
        }
        .sheet(isPresented: $showingShareSheet) {
            if let share = share {
                CloudSharingView(
                    share: share,
                    container: container,
                    onDismiss: {
                        showingShareSheet = false
                        self.share = nil
                    }
                )
            }
        }
        .errorAlert($error)
    }

    private func prepareShare() async {
        isLoading = true
        defer { isLoading = false }

        // Check if already shared
        if let existingShare = sharingService.getShare(for: caree, in: modelContext) {
            share = existingShare
            showingShareSheet = true
            return
        }

        // Create the share before presenting UICloudSharingController
        do {
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
            let database = container.privateCloudDatabase

            let predicate = NSPredicate(format: "CD_id == %@", caree.id.uuidString)
            let query = CKQuery(recordType: "CD_Caree", predicate: predicate)

            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)

            guard let firstMatch = matchResults.first else {
                throw NSError(domain: "CareeShareButton", code: -1, userInfo: [NSLocalizedDescriptionKey: "Caree record not found in CloudKit. Please wait for sync to complete."])
            }

            let (_, result) = firstMatch
            guard case .success(let record) = result else {
                if case .failure(let error) = result {
                    throw error
                }
                throw NSError(domain: "CareeShareButton", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch record"])
            }

            // Create a share for this record
            let newShare = CKShare(rootRecord: record)
            newShare[CKShare.SystemFieldKey.title] = record["CD_name"] as? CKRecordValue ?? "Caree" as CKRecordValue
            newShare.publicPermission = .none

            // Save both the record and share together
            let (savedRecords, _) = try await database.modifyRecords(
                saving: [record, newShare],
                deleting: [],
                savePolicy: .changedKeys
            )

            // Find the saved share
            var savedShare: CKShare?
            for (recordID, result) in savedRecords {
                if case .success(let savedRecord) = result, let share = savedRecord as? CKShare {
                    savedShare = share
                    break
                }
            }

            guard let finalShare = savedShare else {
                throw NSError(domain: "CareeShareButton", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to save share"])
            }

            // Set the share and present the sheet
            share = finalShare
            showingShareSheet = true

        } catch {
            self.error = error
        }
    }
}

#Preview {
    CareeShareButton(caree: PreviewData.sampleCaree, isSynced: true)
        .modelContainer(PreviewContainer.shared)
}
#endif
