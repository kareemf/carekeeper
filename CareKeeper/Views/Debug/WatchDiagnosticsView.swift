import SwiftUI
import UniformTypeIdentifiers

/// Debug view to read and share diagnostic data from watchOS app
/// Reads MetricKit payloads exported to app group by MetricsManager
struct WatchDiagnosticsView: View {

    @State private var diagnosticFiles: [DiagnosticFile] = []
    @State private var isLoading = false
    @State private var shareItem: ShareItem?

    struct DiagnosticFile: Identifiable {
        let id = UUID()
        let url: URL
        let filename: String
        let date: Date
        let type: String  // "diagnostic" or "metric"
        let size: Int64
    }

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if diagnosticFiles.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text("No Diagnostics Found")
                            .font(.headline)

                        Text("Diagnostic data from your watch will appear here. Make sure the watch app has been running on a physical device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else {
                Section(header: Text("Crash & Hang Diagnostics")) {
                    ForEach(diagnosticFiles.filter { $0.type == "diagnostic" }) { file in
                        diagnosticRow(file)
                    }
                }

                Section(header: Text("Performance Metrics")) {
                    ForEach(diagnosticFiles.filter { $0.type == "metric" }) { file in
                        diagnosticRow(file)
                    }
                }

                Section {
                    Button(action: shareAllDiagnostics) {
                        Label("Share All Diagnostics", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive, action: deleteAllDiagnostics) {
                        Label("Delete All Diagnostics", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Watch Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    loadDiagnostics()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear {
            loadDiagnostics()
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ file: DiagnosticFile) -> some View {
        Button {
            shareItem = ShareItem(url: file.url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: file.type == "diagnostic" ? "exclamationmark.triangle.fill" : "chart.bar.fill")
                        .foregroundColor(file.type == "diagnostic" ? .red : .blue)

                    Text(file.filename)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text(formatFileSize(file.size))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(file.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                + Text(" · ")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                + Text(file.date, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteDiagnostic(file)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func loadDiagnostics() {
        isLoading = true

        Task {
            let files = await loadDiagnosticFiles()

            await MainActor.run {
                diagnosticFiles = files
                isLoading = false
            }
        }
    }

    private func loadDiagnosticFiles() async -> [DiagnosticFile] {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID
        ) else {
            return []
        }

        let diagnosticsURL = containerURL.appendingPathComponent("diagnostics", isDirectory: true)
        var allFiles: [DiagnosticFile] = []

        // Load from both subdirectories
        for subdirectory in ["diagnostic", "metric"] {
            let subdirURL = diagnosticsURL.appendingPathComponent(subdirectory, isDirectory: true)

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: subdirURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            ) else {
                continue
            }

            for fileURL in files {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                      let date = resourceValues.creationDate,
                      let size = resourceValues.fileSize else {
                    continue
                }

                allFiles.append(DiagnosticFile(
                    url: fileURL,
                    filename: fileURL.lastPathComponent,
                    date: date,
                    type: subdirectory,
                    size: Int64(size)
                ))
            }
        }

        // Sort by date (newest first)
        return allFiles.sorted { $0.date > $1.date }
    }

    private func shareAllDiagnostics() {
        let urls = diagnosticFiles.map { $0.url }
        guard !urls.isEmpty else { return }

        // Create a temporary directory with all files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-export-\(Date().timeIntervalSince1970)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            for file in diagnosticFiles {
                let destURL = tempDir.appendingPathComponent(file.filename)
                try FileManager.default.copyItem(at: file.url, to: destURL)
            }

            shareItem = ShareItem(url: tempDir)
        } catch {
            AppLogger.app.error("❌ Failed to prepare diagnostics for sharing: \(error.localizedDescription)")
        }
    }

    private func deleteDiagnostic(_ file: DiagnosticFile) {
        do {
            try FileManager.default.removeItem(at: file.url)
            diagnosticFiles.removeAll { $0.id == file.id }
        } catch {
            AppLogger.app.error("❌ Failed to delete diagnostic: \(error.localizedDescription)")
        }
    }

    private func deleteAllDiagnostics() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID
        ) else {
            return
        }

        let diagnosticsURL = containerURL.appendingPathComponent("diagnostics", isDirectory: true)

        do {
            try FileManager.default.removeItem(at: diagnosticsURL)
            diagnosticFiles.removeAll()
        } catch {
            AppLogger.app.error("❌ Failed to delete all diagnostics: \(error.localizedDescription)")
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// UIKit ShareSheet wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

#Preview {
    NavigationStack {
        WatchDiagnosticsView()
    }
}
