import Foundation
import SwiftData

/// Coordinates the migration from hybrid SwiftData+CloudKit to Pure CloudKit architecture
/// Orchestrates: Export → Zone Reset → Import → Cache Refresh
@MainActor
class DataMigrationCoordinator: ObservableObject {

    // MARK: - Published Properties

    @Published var migrationState: MigrationState = .notStarted
    @Published var currentStep: MigrationStep = .idle
    @Published var progress: Double = 0.0
    @Published var error: Error?

    // MARK: - Private Properties

    private let modelContext: ModelContext
    private let cloudKitService: CloudKitDataService
    private let cacheService: LocalCacheService
    private let logger = AppLogger.cloudkit

    // MARK: - Initialization

    init(modelContext: ModelContext, cloudKitService: CloudKitDataService, cacheService: LocalCacheService) {
        self.modelContext = modelContext
        self.cloudKitService = cloudKitService
        self.cacheService = cacheService
    }

    // MARK: - Migration Control

    /// Check if migration is needed
    /// Migration is needed if there are carees without proper CloudKit metadata
    func needsMigration() -> Bool {
        do {
            let fetchDescriptor = FetchDescriptor<Caree>()
            let allCarees = try modelContext.fetch(fetchDescriptor)

            // If any caree is missing cloudKitRecordID, migration is needed
            let needsMigration = allCarees.contains { $0.cloudKitRecordID == nil || $0.cloudKitRecordID!.isEmpty }

            logger.info("Migration check: \(needsMigration ? "NEEDED" : "not needed") (\(allCarees.count) carees)")
            return needsMigration

        } catch {
            logger.error("Failed to check migration status: \(error.localizedDescription)")
            return false // Assume no migration needed if check fails
        }
    }

    /// Start the migration process
    func startMigration() async {
        logger.info("🚀 Starting data migration to Pure CloudKit")
        migrationState = .inProgress
        currentStep = .exporting
        progress = 0.0
        error = nil

        do {
            // Step 1: Export all current data to temp JSON
            try await exportData()
            progress = 0.2

            // Step 2: Delete custom CloudKit zone (clean slate)
            currentStep = .deletingZone
            try await deleteZone()
            progress = 0.4

            // Step 3: Recreate zone and import data
            currentStep = .importingData
            try await importData()
            progress = 0.7

            // Step 4: Clear local SwiftData cache
            currentStep = .clearingCache
            try await clearCache()
            progress = 0.85

            // Step 5: Refresh cache from CloudKit
            currentStep = .refreshingCache
            try await refreshCache()
            progress = 1.0

            // Migration complete!
            currentStep = .completed
            migrationState = .completed
            logger.info("✅ Data migration completed successfully")

        } catch {
            logger.error("❌ Migration failed: \(error.localizedDescription)")
            self.error = error
            migrationState = .failed
            currentStep = .failed
        }
    }

    // MARK: - Migration Steps

    private var tempExportURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).json")
    }

    /// Step 1: Export all data to temporary JSON file
    private func exportData() async throws {
        logger.info("[1/5] Exporting current data...")

        let exportService = MigrationExportService(modelContext: modelContext)
        let exportURL = tempExportURL

        try exportService.exportAllCarees(to: exportURL)

        // Store URL for later import
        UserDefaults.standard.set(exportURL.path, forKey: "migrationExportPath")

        logger.info("✅ Export complete: \(exportURL.path)")
    }

    /// Step 2: Delete custom CloudKit zone (destroys all records)
    private func deleteZone() async throws {
        logger.info("[2/5] Deleting old CloudKit zone...")

        try await cloudKitService.deleteCustomZone()

        // Wait a moment for deletion to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Recreate the zone immediately
        try await cloudKitService.recreateCustomZone()

        logger.info("✅ Zone reset complete")
    }

    /// Step 3: Import data from JSON (creates fresh CloudKit records)
    private func importData() async throws {
        logger.info("[3/5] Importing data with proper parent references...")

        guard let exportPath = UserDefaults.standard.string(forKey: "migrationExportPath"),
              FileManager.default.fileExists(atPath: exportPath) else {
            throw MigrationError.exportFileNotFound
        }

        let exportURL = URL(fileURLWithPath: exportPath)
        let importService = CareeImportService(cloudKitService: cloudKitService)

        try await importService.importFromJSON(at: exportURL)

        // Clean up temp file
        try? FileManager.default.removeItem(at: exportURL)
        UserDefaults.standard.removeObject(forKey: "migrationExportPath")

        logger.info("✅ Import complete")
    }

    /// Step 4: Clear local SwiftData cache
    private func clearCache() async throws {
        logger.info("[4/5] Clearing local cache...")

        try await cacheService.clearCache()

        logger.info("✅ Cache cleared")
    }

    /// Step 5: Refresh cache from CloudKit
    private func refreshCache() async throws {
        logger.info("[5/5] Refreshing from CloudKit...")

        // Fetch all carees from CloudKit and cache them
        let carees = try await cloudKitService.fetchAllCarees()

        for caree in carees {
            try await cacheService.cacheCaree(caree, isShared: false)
        }

        // Refresh published properties
        try await cacheService.refreshCache()

        logger.info("✅ Cache refreshed with \(carees.count) carees")
    }

    // MARK: - Reset

    /// Reset migration state (for retry after failure)
    func reset() {
        migrationState = .notStarted
        currentStep = .idle
        progress = 0.0
        error = nil

        // Clean up any leftover temp files
        if let exportPath = UserDefaults.standard.string(forKey: "migrationExportPath") {
            try? FileManager.default.removeItem(atPath: exportPath)
            UserDefaults.standard.removeObject(forKey: "migrationExportPath")
        }
    }
}

// MARK: - Migration State

enum MigrationState: Equatable {
    case notStarted
    case inProgress
    case completed
    case failed
}

enum MigrationStep: Equatable {
    case idle
    case exporting
    case deletingZone
    case importingData
    case clearingCache
    case refreshingCache
    case completed
    case failed

    var description: String {
        switch self {
        case .idle:
            return "Ready to migrate"
        case .exporting:
            return "Exporting your data..."
        case .deletingZone:
            return "Resetting CloudKit zone..."
        case .importingData:
            return "Importing with fixes..."
        case .clearingCache:
            return "Clearing local cache..."
        case .refreshingCache:
            return "Refreshing from CloudKit..."
        case .completed:
            return "Migration complete!"
        case .failed:
            return "Migration failed"
        }
    }

    var stepNumber: String {
        switch self {
        case .exporting: return "[1/5]"
        case .deletingZone: return "[2/5]"
        case .importingData: return "[3/5]"
        case .clearingCache: return "[4/5]"
        case .refreshingCache: return "[5/5]"
        case .completed: return "✅"
        case .failed: return "❌"
        case .idle: return ""
        }
    }
}

// MARK: - Migration Errors

enum MigrationError: LocalizedError {
    case exportFileNotFound
    case noDataToMigrate

    var errorDescription: String? {
        switch self {
        case .exportFileNotFound:
            return "Migration export file not found. Please restart the migration."
        case .noDataToMigrate:
            return "No data found to migrate."
        }
    }
}
