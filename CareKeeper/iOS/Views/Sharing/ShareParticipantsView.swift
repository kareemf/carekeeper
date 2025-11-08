import CloudKit
import SwiftUI

struct ShareParticipantsView: View {
    let share: CKShare
    let onRemoveParticipant: (CKShare.Participant) async throws -> Void

    @State private var participants: [CKShare.Participant] = []
    @State private var error: Error?
    @State private var removingParticipant: CKShare.Participant?

    private let sharingService = CloudKitSharingService()

    var body: some View {
        List {
            Section {
                ownerRow
            } header: {
                Text(NSLocalizedString("Owner", comment: "Owner section header"))
            }

            if !otherParticipants.isEmpty {
                Section {
                    ForEach(otherParticipants, id: \.userIdentity.userRecordID) { participant in
                        participantRow(participant)
                    }
                } header: {
                    Text(NSLocalizedString("Participants", comment: "Participants section header"))
                }
            } else {
                Section {
                    Text(NSLocalizedString("No participants yet", comment: "Empty participants message"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }

            Section {
                shareURLRow
            } header: {
                Text(NSLocalizedString("Share Link", comment: "Share link section header"))
            } footer: {
                Text(NSLocalizedString(
                    "Share this link to invite others to collaborate on this caree.",
                    comment: "Share link footer"
                ))
            }
        }
        .navigationTitle(NSLocalizedString("Manage Sharing", comment: "Manage sharing title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadParticipants()
        }
        .errorAlert($error)
    }

    private var ownerRow: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading) {
                if let name = share.owner.userIdentity.nameComponents?.formatted() {
                    Text(name)
                        .font(.body)
                } else {
                    Text(NSLocalizedString("Owner", comment: "Owner label"))
                        .font(.body)
                }

                Text(NSLocalizedString("Owner", comment: "Role: owner"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if sharingService.isOwner(of: share) {
                Text(NSLocalizedString("You", comment: "You indicator"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func participantRow(_ participant: CKShare.Participant) -> some View {
        HStack {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                if let name = participant.userIdentity.nameComponents?.formatted() {
                    Text(name)
                        .font(.body)
                } else {
                    Text(NSLocalizedString("Participant", comment: "Participant label"))
                        .font(.body)
                }

                Text(participantPermissionText(participant))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if sharingService.isOwner(of: share) {
                Button(role: .destructive) {
                    removeParticipant(participant)
                } label: {
                    if removingParticipant == participant {
                        ProgressView()
                    } else {
                        Text(NSLocalizedString("Remove", comment: "Remove participant button"))
                            .font(.caption)
                    }
                }
                .disabled(removingParticipant != nil)
            }
        }
    }

    private var shareURLRow: some View {
        HStack {
            if let url = sharingService.getShareURL(for: share) {
                ShareLink(item: url) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(NSLocalizedString("Share Link", comment: "Share link button"))
                    }
                }
            } else {
                Text(NSLocalizedString("Share link unavailable", comment: "Share link unavailable"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var otherParticipants: [CKShare.Participant] {
        participants.filter { $0 != share.owner }
    }

    private func loadParticipants() {
        participants = sharingService.fetchParticipants(for: share)
    }

    private func participantPermissionText(_ participant: CKShare.Participant) -> String {
        switch participant.permission {
        case .readOnly:
            return NSLocalizedString("Read only", comment: "Permission: read only")
        case .readWrite:
            return NSLocalizedString("Can edit", comment: "Permission: can edit")
        case .none:
            return NSLocalizedString("No access", comment: "Permission: no access")
        case .unknown:
            return NSLocalizedString("Unknown", comment: "Permission: unknown")
        @unknown default:
            return NSLocalizedString("Unknown", comment: "Permission: unknown")
        }
    }

    private func removeParticipant(_ participant: CKShare.Participant) {
        removingParticipant = participant

        Task {
            do {
                try await onRemoveParticipant(participant)
                loadParticipants()
                removingParticipant = nil
            } catch {
                self.error = AppError.deleteFailed(error.localizedDescription)
                removingParticipant = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        // Preview requires a real CKShare which is difficult to mock
        // This is a placeholder for development
        Text("Share participants view")
    }
}
