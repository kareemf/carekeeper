import Foundation
import SwiftData

/// Service to import Carees from JSON and create CloudKit records
/// Used for data migration and backup/restore functionality
@MainActor
class CareeImportService: ObservableObject {
    private let cloudKitService: CloudKitDataService
    private let logger = AppLogger.cloudkit

    // Progress tracking
    @Published var progress: ImportProgress = .idle

    init(cloudKitService: CloudKitDataService) {
        self.cloudKitService = cloudKitService
    }

    /// Import carees from JSON file, creating CloudKit records
    /// - Parameter url: URL to JSON file
    /// - Throws: Errors during parsing or CloudKit creation
    func importFromJSON(at url: URL) async throws {
        logger.info("Starting import from \(url.lastPathComponent)")

        // Step 1: Read and parse JSON
        progress = .reading
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let exportedData = try decoder.decode(ExportedData.self, from: data)

        logger.info("Parsed \(exportedData.carees.count) carees from JSON")

        // Step 2: Import each caree with its children
        let totalRecords = exportedData.carees.reduce(0) { count, caree in
            count + 1 + caree.activityTypes.count + caree.activities.count
        }

        var importedRecords = 0

        progress = .importing(current: 0, total: totalRecords)

        for exportedCaree in exportedData.carees {
            try await importCaree(exportedCaree, importedRecords: &importedRecords, totalRecords: totalRecords)
        }

        progress = .completed(recordCount: importedRecords)
        logger.info("Import completed: \(importedRecords) records created")
    }

    /// Import a single caree with all its activity types and activities
    private func importCaree(_ exportedCaree: ExportedCaree, importedRecords: inout Int, totalRecords: Int) async throws {
        logger.info("Importing caree: \(exportedCaree.name)")

        // Create Caree in CloudKit (not shared during import)
        let caree = try await cloudKitService.createCaree(
            name: exportedCaree.name,
            imageData: exportedCaree.imageData,
            listOrder: exportedCaree.listOrder
        )

        importedRecords += 1
        progress = .importing(current: importedRecords, total: totalRecords)

        // Import ActivityTypes
        var activityTypeMap: [UUID: ActivityType] = [:] // Map old IDs to new instances

        for exportedType in exportedCaree.activityTypes {
            let activityType = try await importActivityType(exportedType, caree: caree)
            activityTypeMap[exportedType.id] = activityType

            importedRecords += 1
            progress = .importing(current: importedRecords, total: totalRecords)
        }

        // Import Activities
        for exportedActivity in exportedCaree.activities {
            guard let activityType = activityTypeMap[exportedActivity.activityTypeID] else {
                logger.error("ActivityType not found for activity: \(exportedActivity.activityTypeID)")
                continue
            }

            try await importActivity(exportedActivity, caree: caree, activityType: activityType)

            importedRecords += 1
            progress = .importing(current: importedRecords, total: totalRecords)
        }
    }

    /// Import a single activity type
    private func importActivityType(_ exported: ExportedActivityType, caree: Caree) async throws -> ActivityType {
        try await cloudKitService.createActivityType(
            for: caree,
            name: exported.name,
            icon: exported.icon,
            hasQuantity: exported.hasQuantity,
            quantityUnit: exported.quantityUnit,
            hasLocation: exported.hasLocation,
            listOrder: exported.listOrder,
            isShared: false
        )
    }

    /// Import a single activity
    private func importActivity(_ exported: ExportedActivity, caree: Caree, activityType: ActivityType) async throws {
        _ = try await cloudKitService.createActivity(
            for: caree,
            activityType: activityType,
            dateTime: exported.dateTime,
            notes: exported.notes,
            quantity: exported.quantity,
            latitude: exported.latitude,
            longitude: exported.longitude,
            isShared: false
        )
    }
}

// MARK: - Progress Tracking

enum ImportProgress: Equatable {
    case idle
    case reading
    case importing(current: Int, total: Int)
    case completed(recordCount: Int)
    case failed(error: String)

    var percentage: Double {
        switch self {
        case .idle, .reading:
            return 0
        case let .importing(current, total):
            guard total > 0 else { return 0 }
            return Double(current) / Double(total)
        case .completed:
            return 1.0
        case .failed:
            return 0
        }
    }

    var description: String {
        switch self {
        case .idle:
            "Ready to import"
        case .reading:
            "Reading file..."
        case let .importing(current, total):
            "Importing \(current) of \(total) records..."
        case let .completed(count):
            "Imported \(count) records successfully"
        case let .failed(error):
            "Import failed: \(error)"
        }
    }
}

// Note: ExportedData, ExportedCaree, ExportedActivityType, ExportedActivity
// are defined in CareeExportService.swift and shared between import/export
