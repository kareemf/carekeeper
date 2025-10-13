import SwiftUI
import SwiftData
import Combine

struct CareeListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCaree = false
    @State private var careeToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false
    @State private var error: Error?

    // Pure CloudKit architecture: Cache service as source of truth
    @State private var cacheService: LocalCacheService?
    @StateObject private var cloudKitService = CloudKitDataService()
    @StateObject private var sharedRecordsService = CloudKitSharedRecordsService()

    // Data migration (iOS only)
    #if os(iOS)
    @State private var migrationCoordinator: DataMigrationCoordinator?
    @State private var showingMigration = false
    #endif

    // Backup/Restore (iOS only)
    #if os(iOS)
    @State private var showingExport = false
    @State private var exportFileURL: URL?
    @State private var showingImport = false
    @State private var isImporting = false
    @State private var importProgress: ImportProgress = .idle
    #endif

    // Combined list of all carees from cache
    private var allCarees: [Caree] {
        guard let cacheService = cacheService else { return [] }
        return cacheService.myCarees + cacheService.sharedCarees
    }
    
    var body: some View {
        NavigationView {
            Group {
                if allCarees.isEmpty {
                    emptyStateView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    careeListView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: allCarees.isEmpty)
            .navigationTitle(NSLocalizedString("Carees", comment: "Navigation title for carees list"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SyncStatusIndicator()
                }

                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            exportAllCarees()
                        }) {
                            Label("Export Backup", systemImage: "square.and.arrow.up")
                        }

                        Button(action: {
                            showingImport = true
                        }) {
                            Label("Import Backup", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                #endif

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showingAddCaree = true
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showingAddCaree) {
                CareeEditView()
                    .presentationDragIndicator(.visible)
            }
            #if os(iOS)
            .sheet(isPresented: $showingMigration, onDismiss: {
                // Reload data after migration completes
                Task {
                    await refreshAllCarees()
                }
            }) {
                if let migrationCoordinator = migrationCoordinator {
                    DataMigrationView(coordinator: migrationCoordinator, isPresented: $showingMigration)
                }
            }
            .sheet(isPresented: $showingExport) {
                if let exportFileURL = exportFileURL {
                    ShareSheet(items: [exportFileURL])
                }
            }
            .fileImporter(
                isPresented: $showingImport,
                allowedContentTypes: [.json],
                onCompletion: { result in
                    handleImport(result: result)
                }
            )
            .sheet(isPresented: $isImporting) {
                ImportProgressView(progress: importProgress)
            }
            #endif
            .confirmationDialog(
                NSLocalizedString("Delete Caree?", comment: "Delete caree confirmation title"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                    if let offsets = careeToDelete {
                        Task { @MainActor in
                            await deleteCarees(offsets: offsets)
                            careeToDelete = nil
                        }
                    }
                }
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                    careeToDelete = nil
                }
            } message: {
                Text(NSLocalizedString("This will delete all activity types and activities. This cannot be undone.", comment: "Delete caree confirmation message"))
            }
            .task {
                // Initialize cache service with model context
                if cacheService == nil {
                    cacheService = LocalCacheService(modelContext: modelContext)
                    cloudKitService.setCacheService(cacheService!)
                }

                #if os(iOS)
                // Initialize migration coordinator (iOS only)
                if migrationCoordinator == nil, let cacheService = cacheService {
                    migrationCoordinator = DataMigrationCoordinator(
                        modelContext: modelContext,
                        cloudKitService: cloudKitService,
                        cacheService: cacheService
                    )
                }

                // Check if migration is needed
                if let coordinator = migrationCoordinator, coordinator.needsMigration() {
                    showingMigration = true
                    return // Don't load data until migration is complete
                }
                #endif

                // Initial data load
                await refreshAllCarees()
            }
            .onReceive(sharedRecordsService.$error) { newError in
                if let newError = newError {
                    error = newError
                }
            }
            .errorAlert($error)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .symbolEffect(.bounce, value: allCarees.isEmpty)

            Text(NSLocalizedString("No Carees", comment: "Empty state title"))
                .font(.title2)
                .fontWeight(.medium)

            Text(NSLocalizedString("Create your first caree and set up activity types to start tracking.",
                                 comment: "Empty state description"))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(NSLocalizedString("Add Caree", comment: "CTA button in empty state")) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showingAddCaree = true
                }
            }
            .buttonStyle(.borderedProminent)
            .scaleEffect(showingAddCaree ? 0.95 : 1.0)
        }
        .padding()
    }
    
    private var careeListView: some View {
        List {
            ForEach(allCarees) { caree in
                NavigationLink(destination: CareeDetailView(careeID: caree.id)) {
                    CareeListRowView(
                        caree: caree,
                        isShared: caree.isShared  // Use cache metadata
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
            .onDelete { offsets in
                careeToDelete = offsets
                showingDeleteConfirmation = true
            }
            .onMove(perform: moveCarees)
        }
        .refreshable {
            await refreshAllCarees()
        }
        .animation(.easeInOut(duration: 0.3), value: allCarees.map { $0.id })
    }

    private func refreshAllCarees() async {
        guard let cacheService = cacheService else { return }

        // Fetch shared carees from CloudKit and update cache
        await sharedRecordsService.fetchSharedCarees()

        // Cache shared carees
        for sharedCaree in sharedRecordsService.sharedCarees {
            do {
                try await cacheService.cacheCaree(sharedCaree, isShared: true)
            } catch {
                self.error = error
            }
        }

        // Refresh cache to update published properties
        try? await cacheService.refreshCache()
    }
    
    @MainActor
    private func deleteCarees(offsets: IndexSet) async {
        let sharingService = CloudKitSharingService()

        // Resolve indices to concrete Caree instances first
        let itemsToConsider = offsets.compactMap { index in
            allCarees.indices.contains(index) ? allCarees[index] : nil
        }

        // Check permissions asynchronously (owner can delete)
        var deletable: [Caree] = []
        for caree in itemsToConsider {
            let allowed = await sharingService.canDelete(caree: caree, in: modelContext)
            if allowed {
                deletable.append(caree)
            } else {
                // Show error - user doesn't have permission to delete
                error = AppError.invalidInput("You don't have permission to delete this caree")
            }
        }

        // Pure CloudKit: Delete from CloudKit first, then cache
        withAnimation(.easeInOut(duration: 0.3)) {
            for caree in deletable {
                Task {
                    do {
                        // Determine if this is a shared caree
                        let isShared = caree.isShared

                        // Delete from CloudKit
                        try await cloudKitService.deleteCaree(caree, isShared: isShared)

                        // Cache is automatically updated by CloudKitDataService
                    } catch {
                        self.error = error
                    }
                }
            }
        }
    }
    
    private func moveCarees(from source: IndexSet, to destination: Int) {
        // Only allow reordering of my carees (not shared carees)
        // Shared carees maintain the owner's listOrder
        guard let cacheService = cacheService else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            var updatedCarees = cacheService.myCarees
            updatedCarees.move(fromOffsets: source, toOffset: destination)

            for (index, caree) in updatedCarees.enumerated() {
                caree.listOrder = index
            }
        }
    }

    // MARK: - Backup/Restore

    #if os(iOS)
    private func exportAllCarees() {
        do {
            let exportService = CareeExportService()
            let filename = exportService.generateFilename(careeCount: allCarees.count)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            try exportService.exportAllCarees(to: tempURL, modelContext: modelContext)

            exportFileURL = tempURL
            showingExport = true
        } catch {
            self.error = AppError.saveFailed("Export failed: \(error.localizedDescription)")
        }
    }

    private func handleImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importProgress = .reading
            isImporting = true

            Task {
                do {
                    // Start accessing security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        throw AppError.invalidInput("Unable to access file")
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let importService = CareeImportService(cloudKitService: cloudKitService)
                    try await importService.importFromJSON(at: url)

                    // Refresh UI
                    await refreshAllCarees()

                    await MainActor.run {
                        isImporting = false
                        importProgress = .idle
                    }
                } catch {
                    await MainActor.run {
                        self.error = AppError.saveFailed("Import failed: \(error.localizedDescription)")
                        isImporting = false
                        importProgress = .idle
                    }
                }
            }

        case .failure(let error):
            self.error = AppError.saveFailed("Failed to select file: \(error.localizedDescription)")
        }
    }
    #endif
}

#Preview {
    NavigationView {
        CareeListView()
    }
    .modelContainer(PreviewContainer.shared)
}
