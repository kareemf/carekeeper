import SwiftUI

struct SyncStatusIndicator: View {
    @State private var syncMonitor = CloudKitSyncMonitor.shared
    @State private var isRetrying = false

    var body: some View {
        Group {
            switch syncMonitor.status {
            case .idle:
                EmptyView()

            case .syncing, .checking:
                syncingView

            case .offline, .accountIssue:
                issueView
            }
        }
    }

    private var syncingView: some View {
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
            // Provide immediate visual feedback
            isRetrying = true
            syncMonitor.retry()

            // Reset after delay to allow retry again if needed
            Task {
                try? await Task.sleep(for: .seconds(2))
                isRetrying = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: syncMonitor.status.systemImage)
                    .font(.caption)
                Text(syncMonitor.status.displayMessage)
                    .font(.caption2)
            }
            .foregroundColor(syncMonitor.status.color)
            .opacity(isRetrying ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isRetrying)
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
