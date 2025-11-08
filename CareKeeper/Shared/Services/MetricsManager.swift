#if canImport(MetricKit)
    import Foundation
    import MetricKit
    import os.log

    /// Manages MetricKit crash and diagnostic payload collection
    /// Exports diagnostics to app group for cross-device viewing
    @MainActor
    class MetricsManager: NSObject, MXMetricManagerSubscriber {
        static let shared = MetricsManager()
        private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "metrics")

        override private init() {
            super.init()
            #if !targetEnvironment(simulator)
                // MetricKit only works on physical devices
                MXMetricManager.shared.add(self)
                logger.info("📊 MetricKit subscriber registered")
            #else
                logger.info("📊 MetricKit disabled in simulator")
            #endif
        }

        deinit {
            #if !targetEnvironment(simulator)
                MXMetricManager.shared.remove(self)
            #endif
        }

        // MARK: - MXMetricManagerSubscriber

        nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
            Task { @MainActor in
                logger.info("📊 Received \(payloads.count) diagnostic payload(s)")

                for payload in payloads {
                    await processDiagnosticPayload(payload)
                }
            }
        }

        nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
            Task { @MainActor in
                logger.info("📊 Received \(payloads.count) metric payload(s)")

                for payload in payloads {
                    await processMetricPayload(payload)
                }
            }
        }

        // MARK: - Payload Processing

        private func processDiagnosticPayload(_ payload: MXDiagnosticPayload) async {
            let jsonData = payload.jsonRepresentation()

            let timestamp = payload.timeStampEnd.timeIntervalSince1970
            let filename = "diagnostic-\(Int(timestamp)).json"

            await saveDiagnostic(jsonData, filename: filename, type: "diagnostic")

            // Log summary
            if let crashDiagnostics = payload.crashDiagnostics, !crashDiagnostics.isEmpty {
                logger.error("🔴 Crash diagnostics found: \(crashDiagnostics.count) crash(es)")
            }
            if let hangDiagnostics = payload.hangDiagnostics, !hangDiagnostics.isEmpty {
                logger.warning("🟡 Hang diagnostics found: \(hangDiagnostics.count) hang(s)")
            }
        }

        private func processMetricPayload(_ payload: MXMetricPayload) async {
            let jsonData = payload.jsonRepresentation()

            let timestamp = payload.timeStampEnd.timeIntervalSince1970
            let filename = "metric-\(Int(timestamp)).json"

            await saveDiagnostic(jsonData, filename: filename, type: "metric")

            // Log memory metrics if available
            if let memoryMetrics = payload.memoryMetrics {
                let peakMemoryMB = memoryMetrics.peakMemoryUsage.converted(to: UnitInformationStorage.megabytes).value
                logger.info("📊 Peak memory usage: \(String(format: "%.1f", peakMemoryMB)) MB")
            }
        }

        // MARK: - Storage

        private func saveDiagnostic(_ data: Data, filename: String, type: String) async {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID
            ) else {
                logger.error("❌ Failed to access app group container")
                return
            }

            let diagnosticsURL = containerURL
                .appendingPathComponent("diagnostics", isDirectory: true)
                .appendingPathComponent(type, isDirectory: true)

            do {
                try FileManager.default.createDirectory(
                    at: diagnosticsURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                let fileURL = diagnosticsURL.appendingPathComponent(filename)
                try data.write(to: fileURL, options: .atomic)

                logger.info("✅ Saved \(type) to: \(filename)")

                // Clean up old files (keep last 20)
                await cleanupOldDiagnostics(in: diagnosticsURL, keepLatest: 20)

            } catch {
                logger.error("❌ Failed to save \(type): \(error.localizedDescription)")
            }
        }

        private func cleanupOldDiagnostics(in directory: URL, keepLatest: Int) async {
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                )

                // Sort by creation date (newest first)
                let sortedFiles = files.sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }

                // Delete files beyond the keep limit
                for file in sortedFiles.dropFirst(keepLatest) {
                    try FileManager.default.removeItem(at: file)
                    logger.info("🧹 Deleted old diagnostic: \(file.lastPathComponent)")
                }

            } catch {
                logger.error("❌ Failed to cleanup diagnostics: \(error.localizedDescription)")
            }
        }

        // MARK: - Manual Export

        /// Get all diagnostic files for sharing
        func getAllDiagnostics() -> [URL] {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: CloudKitConfig.appGroupID
            ) else {
                return []
            }

            let diagnosticsURL = containerURL.appendingPathComponent("diagnostics", isDirectory: true)

            var allFiles: [URL] = []

            // Get files from both subdirectories
            for subdirectory in ["diagnostic", "metric"] {
                let subdirURL = diagnosticsURL.appendingPathComponent(subdirectory, isDirectory: true)

                if let files = try? FileManager.default.contentsOfDirectory(
                    at: subdirURL,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                ) {
                    allFiles.append(contentsOf: files)
                }
            }

            // Sort by creation date (newest first)
            return allFiles.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
        }
    }

#else

    import Foundation
    import os.log

    /// Fallback MetricsManager for platforms/SDKs where MetricKit is unavailable
    @MainActor
    class MetricsManager: NSObject {
        static let shared = MetricsManager()
        private let logger = Logger(subsystem: "com.kareemf.CareKeeper", category: "metrics")

        override private init() {
            super.init()
            logger.info("📊 MetricKit not available on this platform/SDK; metrics disabled")
        }

        /// No-op: returns an empty list since diagnostics aren’t collected without MetricKit
        func getAllDiagnostics() -> [URL] { [] }
    }

#endif
