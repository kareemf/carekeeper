import Foundation

/// Service for exporting Caree data to JSON format
struct CareeExportService {

    // MARK: - Export Models

    struct ExportCaree: Codable {
        let name: String
        let dateCreated: Date
        let activityTypes: [ExportActivityType]
        let activities: [ExportActivity]

        var exportMetadata: ExportMetadata {
            ExportMetadata(
                exportDate: Date(),
                version: "1.0",
                activityTypesCount: activityTypes.count,
                activitiesCount: activities.count
            )
        }
    }

    struct ExportActivityType: Codable {
        let name: String
        let icon: String?
        let hasQuantity: Bool
        let quantityUnit: String?
        let hasLocation: Bool
        let listOrder: Int
    }

    struct ExportActivity: Codable {
        let activityTypeName: String
        let dateTime: Date
        let notes: String?
        let quantity: Double?
        let quantityUnit: String?
        let latitude: Double?
        let longitude: Double?
    }

    struct ExportMetadata: Codable {
        let exportDate: Date
        let version: String
        let activityTypesCount: Int
        let activitiesCount: Int
    }

    struct ExportData: Codable {
        let metadata: ExportMetadata
        let caree: ExportCaree
    }

    // MARK: - Export Methods

    /// Exports a Caree to JSON Data
    /// - Parameter caree: The caree to export
    /// - Returns: JSON data ready for sharing
    /// - Throws: Encoding errors
    func exportToJSON(caree: Caree) throws -> Data {
        // Convert activity types
        let exportActivityTypes = (caree.activityTypes ?? [])
            .sorted { $0.listOrder < $1.listOrder }
            .map { activityType in
                ExportActivityType(
                    name: activityType.name,
                    icon: activityType.icon,
                    hasQuantity: activityType.hasQuantity,
                    quantityUnit: activityType.quantityUnit,
                    hasLocation: activityType.hasLocation,
                    listOrder: activityType.listOrder
                )
            }

        // Convert activities
        let exportActivities = (caree.activities ?? [])
            .sorted { $0.dateTime > $1.dateTime }
            .map { activity in
                ExportActivity(
                    activityTypeName: activity.activityType?.name ?? "Unknown",
                    dateTime: activity.dateTime,
                    notes: activity.notes,
                    quantity: activity.quantity,
                    quantityUnit: activity.activityType?.quantityUnit,
                    latitude: activity.latitude,
                    longitude: activity.longitude
                )
            }

        // Create export caree
        let exportCaree = ExportCaree(
            name: caree.name,
            dateCreated: caree.dateCreated,
            activityTypes: exportActivityTypes,
            activities: exportActivities
        )

        // Create export data with metadata
        let exportData = ExportData(
            metadata: exportCaree.exportMetadata,
            caree: exportCaree
        )

        // Encode to JSON with pretty printing
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(exportData)
    }

    /// Generates a filename for the export
    /// - Parameter caree: The caree being exported
    /// - Returns: A formatted filename
    func generateFilename(for caree: Caree) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        // Sanitize caree name for filename
        let sanitizedName = caree.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        return "\(sanitizedName)_export_\(dateString).json"
    }
}
