import Foundation
import SwiftData

/// Migration-specific export service
/// Exports ALL carees with UUIDs, images, and full relationship data
/// Used exclusively for data migration to Pure CloudKit architecture
@MainActor
class MigrationExportService {
    private let modelContext: ModelContext
    private let logger = AppLogger.cloudkit

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Export all carees from SwiftData to JSON
    /// - Parameter url: Destination URL for JSON file
    /// - Throws: Errors during fetch or encoding
    func exportAllCarees(to url: URL) throws {
        logger.info("Starting migration export to \(url.lastPathComponent)")

        // Fetch all carees from SwiftData
        let fetchDescriptor = FetchDescriptor<Caree>(
            sortBy: [SortDescriptor(\.listOrder)]
        )
        let allCarees = try modelContext.fetch(fetchDescriptor)

        logger.info("Exporting \(allCarees.count) carees")

        // Convert to exportable format
        let exportedCarees = allCarees.map { caree in
            exportCaree(caree)
        }

        // Create export data structure
        let exportData = ExportedData(
            carees: exportedCarees,
            exportDate: Date(),
            version: "2.0" // Migration format version
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(exportData)
        try data.write(to: url)

        logger.info("Migration export completed: \(data.count) bytes")
    }

    /// Convert a Caree to exportable format
    private func exportCaree(_ caree: Caree) -> ExportedCaree {
        // Export activity types
        let exportedTypes = (caree.activityTypes ?? [])
            .sorted { $0.listOrder < $1.listOrder }
            .map { activityType in
                ExportedActivityType(
                    id: activityType.id,
                    name: activityType.name,
                    icon: activityType.icon,
                    hasQuantity: activityType.hasQuantity,
                    quantityUnit: activityType.quantityUnit,
                    hasLocation: activityType.hasLocation,
                    listOrder: activityType.listOrder,
                    dateCreated: activityType.dateCreated
                )
            }

        // Export activities
        let exportedActivities = (caree.activities ?? [])
            .sorted { $0.dateTime > $1.dateTime }
            .compactMap { activity -> ExportedActivity? in
                guard let activityType = activity.activityType else {
                    logger.warning("Activity \(activity.id) missing activityType, skipping")
                    return nil
                }

                return ExportedActivity(
                    id: activity.id,
                    dateTime: activity.dateTime,
                    notes: activity.notes,
                    quantity: activity.quantity,
                    latitude: activity.latitude,
                    longitude: activity.longitude,
                    activityTypeID: activityType.id,
                    dateCreated: activity.dateCreated
                )
            }

        return ExportedCaree(
            id: caree.id,
            name: caree.name,
            imageData: caree.image, // Include raw image data
            listOrder: caree.listOrder,
            dateCreated: caree.dateCreated,
            activityTypes: exportedTypes,
            activities: exportedActivities
        )
    }
}

// Note: ExportedData, ExportedCaree, ExportedActivityType, ExportedActivity
// are defined in CareeExportService.swift and shared between import/export
