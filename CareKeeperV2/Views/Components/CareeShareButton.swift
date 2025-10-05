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
            print("📤 Share button tapped for caree: \(caree.name) (ID: \(caree.id.uuidString))")
            print("   Sync status: \(isSynced ? "✅ Synced" : "❌ Not synced")")

            // Pre-share validation
            if !isSynced {
                print("⚠️ Showing 'not synced' alert to user")
                showingSyncAlert = true
            } else {
                print("✅ Proceeding with share preparation")
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
                // Existing share
                CloudSharingView(
                    share: share,
                    container: container,
                    onDismiss: {
                        showingShareSheet = false
                        self.share = nil
                    }
                )
            } else {
                // New share - use preparation handler
                CloudSharingView(
                    careeID: caree.id.uuidString,
                    container: container,
                    onDismiss: {
                        showingShareSheet = false
                    }
                )
            }
        }
        .errorAlert($error)
    }

    private func prepareShare() async {
        isLoading = true
        defer { isLoading = false }

        print("📤 Share button tapped for caree: \(caree.name) (ID: \(caree.id.uuidString))")

        // Check if already shared
        if let existingShare = sharingService.getShare(for: caree, in: modelContext) {
            print("✅ Found existing share for caree")
            share = existingShare
        } else {
            print("🆕 No existing share found - will create new share")

            // Check if caree has synced to CloudKit (query by CD_id field)
            do {
                let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
                let database = container.privateCloudDatabase

                let predicate = NSPredicate(format: "CD_id == %@", caree.id.uuidString)
                let query = CKQuery(recordType: "CD_Caree", predicate: predicate)

                let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)

                if let firstMatch = matchResults.first {
                    let (_, result) = firstMatch
                    if case .success(let record) = result {
                        print("✅ Caree record found in CloudKit")
                        print("   CloudKit record ID: \(record.recordID.recordName)")
                        print("   CD_id: \(record["CD_id"] as? String ?? "unknown")")
                    }
                } else {
                    print("⚠️ Caree record not yet synced to CloudKit")
                }
            } catch {
                print("⚠️ Error checking CloudKit sync: \(error.localizedDescription)")
                if let ckError = error as? CKError {
                    print("⚠️ CKError code: \(ckError.code.rawValue)")
                }
            }

            // New share - will be created by UICloudSharingController's preparation handler
            share = nil
        }

        showingShareSheet = true
    }
}

#Preview {
    CareeShareButton(caree: PreviewData.sampleCaree, isSynced: true)
        .modelContainer(PreviewContainer.shared)
}
#endif
