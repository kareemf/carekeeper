import SwiftUI
import SwiftData

#if os(iOS)
/// UI for data migration from hybrid to Pure CloudKit architecture
/// Shows prompt and progress during migration
struct DataMigrationView: View {
    @ObservedObject var coordinator: DataMigrationCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                migrationIcon
                    .font(.system(size: 60))
                    .foregroundColor(iconColor)
                    .symbolEffect(.bounce, value: coordinator.migrationState)

                // Title
                Text(titleText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                // Description
                Text(descriptionText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Progress section
                if coordinator.migrationState == .inProgress {
                    progressSection
                }

                // Error message
                if let error = coordinator.error {
                    errorSection(error: error)
                }

                Spacer()

                // Action buttons
                actionButtons
            }
            .padding()
            .navigationTitle("Data Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if coordinator.migrationState != .inProgress {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var migrationIcon: Image {
        switch coordinator.migrationState {
        case .notStarted:
            return Image(systemName: "arrow.up.circle")
        case .inProgress:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .completed:
            return Image(systemName: "checkmark.circle.fill")
        case .failed:
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var iconColor: Color {
        switch coordinator.migrationState {
        case .notStarted, .inProgress:
            return .accentColor
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var titleText: String {
        switch coordinator.migrationState {
        case .notStarted:
            return NSLocalizedString("Data Upgrade Available", comment: "Migration prompt title")
        case .inProgress:
            return NSLocalizedString("Upgrading Data...", comment: "Migration in progress title")
        case .completed:
            return NSLocalizedString("Upgrade Complete!", comment: "Migration complete title")
        case .failed:
            return NSLocalizedString("Upgrade Failed", comment: "Migration failed title")
        }
    }

    private var descriptionText: String {
        switch coordinator.migrationState {
        case .notStarted:
            return NSLocalizedString("We've improved sync reliability! Tap 'Upgrade Now' to migrate your data to the new system. This takes about 15-30 seconds and will make sharing work correctly.", comment: "Migration prompt description")
        case .inProgress:
            return coordinator.currentStep.description
        case .completed:
            return NSLocalizedString("Your data has been successfully upgraded. Sharing will now work correctly!", comment: "Migration complete description")
        case .failed:
            return NSLocalizedString("The upgrade encountered an error. Your data is safe. You can try again or contact support.", comment: "Migration failed description")
        }
    }

    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: coordinator.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal)

            Text(coordinator.currentStep.stepNumber + " " + coordinator.currentStep.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func errorSection(error: Error) -> some View {
        Text(error.localizedDescription)
            .font(.caption)
            .foregroundColor(.red)
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
    }

    private var actionButtons: some View {
        Group {
            switch coordinator.migrationState {
            case .notStarted:
                Button(action: {
                    Task {
                        await coordinator.startMigration()
                    }
                }) {
                    Text(NSLocalizedString("Upgrade Now", comment: "Start migration button"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

            case .inProgress:
                // No buttons during migration
                EmptyView()

            case .completed:
                Button(action: {
                    isPresented = false
                }) {
                    Text(NSLocalizedString("Done", comment: "Migration complete button"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

            case .failed:
                VStack(spacing: 12) {
                    Button(action: {
                        coordinator.reset()
                        Task {
                            await coordinator.startMigration()
                        }
                    }) {
                        Text(NSLocalizedString("Try Again", comment: "Retry migration button"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        coordinator.reset()
                        isPresented = false
                    }) {
                        Text(NSLocalizedString("Cancel", comment: "Cancel migration button"))
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview("Not Started") {
    DataMigrationView(
        coordinator: {
            let container = try! ModelContainer(for: Caree.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let coordinator = DataMigrationCoordinator(
                modelContext: container.mainContext,
                cloudKitService: CloudKitDataService(),
                cacheService: LocalCacheService(modelContext: container.mainContext)
            )
            return coordinator
        }(),
        isPresented: .constant(true)
    )
}

#Preview("In Progress") {
    DataMigrationView(
        coordinator: {
            let container = try! ModelContainer(for: Caree.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let coordinator = DataMigrationCoordinator(
                modelContext: container.mainContext,
                cloudKitService: CloudKitDataService(),
                cacheService: LocalCacheService(modelContext: container.mainContext)
            )
            coordinator.migrationState = .inProgress
            coordinator.currentStep = .importingData
            coordinator.progress = 0.6
            return coordinator
        }(),
        isPresented: .constant(true)
    )
}

#Preview("Completed") {
    DataMigrationView(
        coordinator: {
            let container = try! ModelContainer(for: Caree.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let coordinator = DataMigrationCoordinator(
                modelContext: container.mainContext,
                cloudKitService: CloudKitDataService(),
                cacheService: LocalCacheService(modelContext: container.mainContext)
            )
            coordinator.migrationState = .completed
            coordinator.currentStep = .completed
            coordinator.progress = 1.0
            return coordinator
        }(),
        isPresented: .constant(true)
    )
}
#endif
