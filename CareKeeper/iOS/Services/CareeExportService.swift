import Foundation

/// Service for exporting Caree data to JSON format (v2.0)
/// Supports both single-caree and all-carees exports with full fidelity
@MainActor
struct CareeExportService {
    private let logger = AppLogger.cloudkit

    // MARK: - Export Methods

    /// Export a single Caree to JSON with full fidelity (v2.0 format)
    /// - Parameter caree: The caree to export
    /// - Returns: JSON data ready for sharing
    /// - Throws: Encoding errors
    func exportCaree(_ caree: Caree) throws -> Data {
        let exportedCaree = convertToExportFormat(caree)

        let exportData = ExportedData(
            carees: [exportedCaree],
            exportDate: Date(),
            version: "2.0"
        )

        return try encodeToJSON(exportData)
    }

    /// Export all Carees to JSON file (v2.0 format)
    /// - Parameters:
    ///   - url: Destination URL for JSON file
    ///   - carees: Carees to export (pass LocalCacheService's myCarees)
    /// - Throws: Errors during encoding
    func exportAllCarees(to url: URL, carees: [Caree]) throws {
        logger.info("Starting export to \(url.lastPathComponent)")
        logger.info("Exporting \(carees.count) carees")

        // Convert to exportable format
        let exportedCarees = carees.map { convertToExportFormat($0) }

        // Create export data structure
        let exportData = ExportedData(
            carees: exportedCarees,
            exportDate: Date(),
            version: "2.0"
        )

        // Encode and write
        let data = try encodeToJSON(exportData)
        try data.write(to: url)

        logger.info("Export completed: \(data.count) bytes")
    }

    /// Generates a filename for the export
    /// - Parameter careeCount: Number of carees being exported
    /// - Returns: A formatted filename
    func generateFilename(careeCount: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        if careeCount == 1 {
            return "carekeeper_export_\(dateString).json"
        } else {
            return "carekeeper_\(careeCount)_carees_\(dateString).json"
        }
    }

    // MARK: - Private Helpers

    /// Convert a Caree to exportable format
    private func convertToExportFormat(_ caree: Caree) -> ExportedCaree {
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
            imageData: caree.image,
            listOrder: caree.listOrder,
            dateCreated: caree.dateCreated,
            activityTypes: exportedTypes,
            activities: exportedActivities
        )
    }

    /// Encode export data to JSON
    private func encodeToJSON(_ exportData: ExportedData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportData)
    }
}

// MARK: - Export Data Structures (v2.0)

/// Root structure for exported JSON (v2.0 format)
struct ExportedData: Codable {
    let carees: [ExportedCaree]
    let exportDate: Date
    let version: String
}

/// Exported Caree with nested children and full fidelity
struct ExportedCaree: Codable {
    let id: UUID
    let name: String
    let imageData: Data?
    let listOrder: Int
    let dateCreated: Date
    let activityTypes: [ExportedActivityType]
    let activities: [ExportedActivity]
}

/// Exported ActivityType with full metadata
struct ExportedActivityType: Codable {
    let id: UUID
    let name: String
    let icon: String?
    let hasQuantity: Bool
    let quantityUnit: String?
    let hasLocation: Bool
    let listOrder: Int
    let dateCreated: Date
}

/// Exported Activity with references by ID
struct ExportedActivity: Codable {
    let id: UUID
    let dateTime: Date
    let notes: String?
    let quantity: Double?
    let latitude: Double?
    let longitude: Double?
    let activityTypeID: UUID
    let dateCreated: Date
}
