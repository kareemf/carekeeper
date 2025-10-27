import Foundation
import CloudKit
import os.log

/// Shared retry logic for CloudKit operations with exponential backoff
/// Handles transient errors automatically with configurable retry attempts
class CloudKitRetryService {

    // MARK: - Configuration

    /// Maximum retry attempts for transient errors (default: 3)
    let maxRetries: Int

    /// Base delay for exponential backoff in seconds (default: 2.0)
    /// Backoff sequence: 2s, 4s, 8s
    let baseRetryDelay: TimeInterval

    private let logger: Logger

    // MARK: - Initialization

    init(
        maxRetries: Int = 3,
        baseRetryDelay: TimeInterval = 2.0,
        subsystem: String = "com.kareemf.CareKeeper",
        category: String = "cloudkit-retry"
    ) {
        self.maxRetries = maxRetries
        self.baseRetryDelay = baseRetryDelay
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    // MARK: - Retry Logic

    /// Execute a CloudKit request with automatic retry for transient errors
    /// Uses exponential backoff: 2s, 4s, 8s (configurable)
    /// - Parameters:
    ///   - operation: Description of the operation for logging
    ///   - block: Async closure to execute (CloudKit operation)
    /// - Returns: Result of the operation
    /// - Throws: Last error if all retries exhausted or non-retryable error
    func retryableRequest<T>(
        operation: String,
        _ block: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                logger.info("☁️ \(operation) (attempt \(attempt + 1)/\(self.maxRetries))")
                let result = try await block()

                if attempt > 0 {
                    logger.info("✅ \(operation) succeeded after \(attempt + 1) attempts")
                }

                return result

            } catch {
                lastError = error

                // Check if error is retryable
                let ckError = error as? CKError
                let isRetryable = ckError?.isRetryable ?? false

                logger.error("❌ \(operation) failed (attempt \(attempt + 1)/\(self.maxRetries)): \(error.localizedDescription)")

                // Log CKError details for debugging
                if let ckError = ckError {
                    logger.error("   CKError code: \(ckError.code.rawValue)")
                    logger.error("   Is retryable: \(isRetryable)")

                    // Log retry after delay if CKError suggests it
                    if let retryAfter = ckError.retryAfterSeconds {
                        logger.info("   CloudKit suggests retry after: \(retryAfter)s")
                    }
                }

                // Don't retry if not a transient error
                guard isRetryable else {
                    logger.error("⚠️ Non-retryable error, failing immediately")
                    throw error
                }

                // Don't retry if this was the last attempt
                guard attempt < maxRetries - 1 else {
                    break
                }

                // Calculate exponential backoff delay
                // Use CloudKit's suggested delay if available, otherwise exponential backoff
                let delay: TimeInterval
                if let ckError = ckError, let retryAfter = ckError.retryAfterSeconds {
                    delay = retryAfter
                    logger.info("⏳ Using CloudKit suggested delay: \(delay)s")
                } else {
                    delay = baseRetryDelay * pow(2.0, Double(attempt))
                    logger.info("⏳ Exponential backoff: waiting \(delay)s before retry...")
                }

                logger.info("⏳ Waiting \(delay)s before retry...")

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // All retries exhausted
        logger.error("❌ \(operation) failed after \(self.maxRetries) attempts")

        throw lastError ?? CKError(.networkFailure)
    }
}
