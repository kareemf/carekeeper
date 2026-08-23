import CloudKit
import Foundation

protocol CloudKitUserRecordIDFetching {
    func fetchUserRecordID(completionHandler: @escaping @Sendable (CKRecord.ID?, Error?) -> Void)
}

extension CKContainer: CloudKitUserRecordIDFetching {}

@MainActor
final class CloudKitUserIdentityService {
    static let shared = CloudKitUserIdentityService()

    private let logger = AppLogger.cloudkit
    private var cachedRecordName: String?

    private init() {}

    init(testing _: Void) {}

    func currentUserRecordName(in container: CKContainer) async -> String? {
        await currentUserRecordName(fetcher: container)
    }

    func currentUserRecordName(fetcher: CloudKitUserRecordIDFetching) async -> String? {
        if let cachedRecordName { return cachedRecordName }
        do {
            let recordID = try await fetchUserRecordID(from: fetcher)
            let recordName = recordID.recordName
            cachedRecordName = recordName
            return recordName
        } catch {
            logger.warning("⚠️ Failed to fetch current user record ID: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchUserRecordID(from fetcher: CloudKitUserRecordIDFetching) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            fetcher.fetchUserRecordID(completionHandler: { recordID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let recordID {
                    continuation.resume(returning: recordID)
                } else {
                    continuation.resume(throwing: AppError.invalidInput("Missing user record ID"))
                }
            })
        }
    }
}
