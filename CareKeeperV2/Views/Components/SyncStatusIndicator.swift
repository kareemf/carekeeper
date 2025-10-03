import SwiftUI

struct SyncStatusIndicator: View {
    @State private var syncMonitor = CloudKitSyncMonitor.shared

    var body: some View {
        Group {
            switch syncMonitor.status {
            case .idle:
                EmptyView()

            case .checking:
                checkingView

            case .offline, .accountIssue:
                issueView
            }
        }
    }

    private var checkingView: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.7)
            Text(syncMonitor.status.displayMessage)
                .font(.caption2)
                .foregroundColor(syncMonitor.status.color)
        }
    }

    private var issueView: some View {
        Button {
            syncMonitor.retry()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: syncMonitor.status.systemImage)
                    .font(.caption)
                Text(syncMonitor.status.displayMessage)
                    .font(.caption2)
            }
            .foregroundColor(syncMonitor.status.color)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        SyncStatusIndicator()

        // Preview different states
        Text("Preview States:")
            .font(.headline)

        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Checking...")
                .font(.caption2)
                .foregroundColor(.blue)
        }

        HStack(spacing: 4) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundColor(.orange)
            Text("Offline")
                .font(.caption2)
                .foregroundColor(.orange)
        }

        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.icloud")
                .font(.caption)
                .foregroundColor(.red)
            Text("iCloud issue")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
    .padding()
}
