import os

/// Centralized logging for CareKeeper app
/// Use these loggers instead of print() to ensure logs appear in Console.app for TestFlight/Release builds
enum AppLogger {
    /// Logger for CloudKit operations (sharing, syncing, notifications)
    static let cloudkit = Logger(subsystem: "com.kareemf.CareKeeper", category: "CloudKit")

    /// Logger for general app lifecycle events
    static let app = Logger(subsystem: "com.kareemf.CareKeeper", category: "App")

    /// Logger for share acceptance and management
    static let sharing = Logger(subsystem: "com.kareemf.CareKeeper", category: "Sharing")
}

// MARK: - Console.app Filtering Guide

/*
 To view logs in Console.app:

 1. Connect device via USB
 2. Open Console.app
 3. Select your device in sidebar
 4. Use these filters:

    All CareKeeper logs:
    subsystem:com.kareemf.CareKeeper

    CloudKit only:
    subsystem:com.kareemf.CareKeeper category:CloudKit

    Sharing only:
    subsystem:com.kareemf.CareKeeper category:Sharing

    Search by emoji:
    subsystem:com.kareemf.CareKeeper AND 📱
 */
