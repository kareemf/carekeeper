import SwiftUI
import SwiftData
import Combine

struct CareeListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCaree = false
    @State private var careeToDelete: IndexSet?
    @State private var showingDeleteConfirmation = false
    @State private var error: Error?
    @State private var deletionProgress: Double = 0.0
    @State private var isDeleting = false
    @State private var reorderTask: Task<Void, Never>?

    // Pure CloudKit architecture: Cache service as source of truth
    @EnvironmentObject private var cloudKitService: CloudKitDataService
    @EnvironmentObject private var sharedRecordsService: CloudKitSharedRecordsService

    // Cache service from cloudKitService (already initialized at app level)
    private var cacheService: LocalCacheService? {
        cloudKitService.cacheService
    }

    private var pendingDeletionCarees: [Caree] {
        guard let offsets = careeToDelete else { return [] }
        return offsets.compactMap { index in
            allCarees.indices.contains(index) ? allCarees[index] : nil
        }
    }

    private var pendingDeletionIncludesShared: Bool {
        pendingDeletionCarees.contains(where: { $0.isShared })
    }

    private var pendingDeletionIncludesOwned: Bool {
        pendingDeletionCarees.contains(where: { !$0.isShared })
    }

    private var deleteConfirmationTitle: String {
        if pendingDeletionIncludesShared && !pendingDeletionIncludesOwned {
            return NSLocalizedString("Leave Shared Caree?", comment: "Leave shared caree confirmation title")
        } else if pendingDeletionIncludesShared {
            return NSLocalizedString("Remove Carees?", comment: "Mixed delete confirmation title")
        } else {
            return NSLocalizedString("Delete Caree?", comment: "Delete caree confirmation title")
        }
    }

    private var deleteConfirmationPrimaryButtonTitle: String {
        if pendingDeletionIncludesShared && !pendingDeletionIncludesOwned {
            return NSLocalizedString("Leave Share", comment: "Leave shared caree confirmation button")
        } else if pendingDeletionIncludesShared {
            return NSLocalizedString("Continue", comment: "Mixed delete confirmation button")
        } else {
            return NSLocalizedString("Delete", comment: "Delete caree confirmation button")
        }
    }

    private var deleteConfirmationMessageText: String {
        switch (pendingDeletionIncludesOwned, pendingDeletionIncludesShared) {
        case (false, false):
            return NSLocalizedString("This will delete all activity types and activities. This cannot be undone.", comment: "Delete caree confirmation message")
        case (true, false):
            return NSLocalizedString("This will delete all activity types and activities. This cannot be undone.", comment: "Delete caree confirmation message")
        case (false, true):
            return NSLocalizedString("You will no longer receive updates for this shared caree. Other participants will retain access.", comment: "Leave shared caree confirmation message")
        case (true, true):
            return NSLocalizedString("Owned carees will be deleted for everyone. Shared carees will be removed from your list.", comment: "Mixed delete confirmation message")
        }
    }

    // Combined list of all carees - updated when cache changes
    @State private var allCarees: [Caree] = []

    // Loading coordination
    @State private var initialLoading = true

    // Show full-screen loading only on initial load when cache is empty
    // Otherwise, show cached content and refresh in background
    private var isLoadingCombined: Bool {
        // Only show full-screen loading if:
        // 1. Initial load is happening, AND
        // 2. Cache is empty (no content to show yet)
        return initialLoading && allCarees.isEmpty
    }

    // Backup/Restore (iOS only)
    #if os(iOS)
    @State private var showingExport = false
    @State private var exportFileURL: URL?
    @State private var showingImport = false
    @State private var isImporting = false
    @State private var importProgress: ImportProgress = .idle
    @State private var importService: CareeImportService?
    @State private var showingHelp = false
    #endif
    
    var body: some View {
        NavigationStack {
            mainContent
        }
    }

    private var mainContent: some View {
        contentView
            .navigationTitle(NSLocalizedString("Carees", comment: "Navigation title for carees list"))
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAddCaree) {
                CareeEditView()
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                deleteConfirmationButtons
            } message: {
                deleteConfirmationMessage
            }
            .modifier(BackupRestoreSheets(
                showingExport: $showingExport,
                exportFileURL: exportFileURL,
                showingImport: $showingImport,
                isImporting: $isImporting,
                importProgress: importProgress,
                handleImport: handleImport,
                showingHelp: $showingHelp
            ))
            .task(initializeTask)
            .onReceive(cloudKitService.$cacheService.compactMap { $0 }) { _ in
                Task {
                    await refreshAllCarees(initial: allCarees.isEmpty)
                }
            }
            .modifier(DataObservers(
                sharedRecordsService: sharedRecordsService,
                cacheService: cacheService,
                cloudKitService: cloudKitService,
                importService: importService,
                onError: { error = $0 },
                onDeletionProgress: { isDeleting = $0; deletionProgress = $1 },
                onImportProgress: { importProgress = $0 },
                onUpdate: updateAllCarees
            ))
            .overlay { deletionProgressOverlay }
            .errorAlert($error)
            .onDisappear {
                reorderTask?.cancel()
            }
    }

    private var contentView: some View {
        Group {
            if isLoadingCombined {
                // Full-screen loading only on initial load with empty cache
                // Otherwise, show cached content and refresh in background (status shown in toolbar)
                VStack(spacing: 16) {
                    ProgressView()
                    Text(NSLocalizedString("Loading carees...", comment: "Loading owned and shared carees message"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if allCarees.isEmpty {
                emptyStateView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                careeListView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoadingCombined)
        .animation(.easeInOut(duration: 0.3), value: allCarees.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            SyncStatusIndicator()
        }

        #if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) {
            backupRestoreMenu
        }
        #endif

        ToolbarItem(placement: .navigationBarTrailing) {
            addButton
        }
    }

    #if os(iOS)
    private var backupRestoreMenu: some View {
        Menu {
            Button(action: { showingHelp = true }) {
                Label("Help", systemImage: "questionmark.circle")
            }

            Divider()

            Button(action: exportAllCarees) {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }

            Button(action: { showingImport = true }) {
                Label("Import Data", systemImage: "square.and.arrow.down")
            }

            Divider()

            NavigationLink {
                WatchDiagnosticsView()
            } label: {
                Label("Watch Diagnostics", systemImage: "chart.bar.doc.horizontal")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    #endif

    private var addButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingAddCaree = true
            }
        }) {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
        }
    }

    private var deleteConfirmationButtons: some View {
        Group {
            Button(deleteConfirmationPrimaryButtonTitle, role: .destructive) {
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
        }
    }

    private var deleteConfirmationMessage: some View {
        Text(deleteConfirmationMessageText)
    }

    @Sendable
    private func initializeTask() async {
        // Initialize import service
        #if os(iOS)
        if importService == nil {
            importService = CareeImportService(cloudKitService: cloudKitService)
        }
        #endif

        // Initial data load (unified)
        await refreshAllCarees(initial: true)
    }

    @ViewBuilder
    private var deletionProgressOverlay: some View {
        if isDeleting {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView(value: deletionProgress) {
                        Text(NSLocalizedString("Deleting Caree...", comment: "Deletion progress title"))
                            .font(.headline)
                    }
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 200)

                    Text("\(Int(deletionProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }
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

    private func updateAllCarees() {
        guard let cacheService = cacheService else {
            allCarees = []
            return
        }
        let newCombined = cacheService.myCarees + cacheService.sharedCarees
        // Only assign when the identity + order actually changed
        if !arraysEqualByID(lhs: allCarees, rhs: newCombined) {
            allCarees = newCombined
        }
    }

    private func refreshAllCarees(initial: Bool = false) async {
        guard let cacheService = cacheService else { return }

        if initial {
            await MainActor.run { initialLoading = true }
        }

        // Fetch shared carees from CloudKit; this will push results into cache internally
        await sharedRecordsService.fetchSharedCarees()

        // Fetch owned carees from CloudKit and update LocalCacheService
        do {
            try await cloudKitService.refreshOwnedCareesFromCloudKit()
        } catch {
            AppLogger.cloudkit.warning("⚠️ Owned refresh failed: \(error.localizedDescription)")
        }

        // Update combined list
        await MainActor.run {
            updateAllCarees()
            if initial {
                initialLoading = false
            }
        }
    }
    
    @MainActor
    private func deleteCarees(offsets: IndexSet) async {
        let sharingService = CloudKitSharingService()

        // Resolve indices to concrete Caree instances first
        let itemsToConsider = offsets.compactMap { index in
            allCarees.indices.contains(index) ? allCarees[index] : nil
        }

        guard !itemsToConsider.isEmpty else { return }

        var ownedCarees: [Caree] = []
        var sharedCareesToLeave: [Caree] = []

        for caree in itemsToConsider {
            if caree.isShared {
                sharedCareesToLeave.append(caree)
            } else {
                let allowed = await sharingService.canDelete(caree: caree, in: modelContext)
                if allowed {
                    ownedCarees.append(caree)
                } else {
                    error = AppError.invalidInput("You don't have permission to delete this caree")
                }
            }
        }

        if !sharedCareesToLeave.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                for caree in sharedCareesToLeave {
                    Task {
                        do {
                            try await sharedRecordsService.leaveShare(for: caree)
                        } catch {
                            await MainActor.run { self.error = error }
                        }
                    }
                }
            }
        }

        if !ownedCarees.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                for caree in ownedCarees {
                    Task {
                        do {
                            try await cloudKitService.deleteCaree(caree, isShared: false)
                        } catch {
                            await MainActor.run { self.error = error }
                        }
                    }
                }
            }
        }
    }
    
    private func moveCarees(from source: IndexSet, to destination: Int) {
        // Only allow reordering of my carees (not shared carees)
        // Shared carees maintain the owner's listOrder
        guard let cacheService = cacheService else { return }

        var ownedCarees = cacheService.myCarees
        let originalIDs = ownedCarees.map(\.id)

        ownedCarees.move(fromOffsets: source, toOffset: destination)
        let newIDs = ownedCarees.map(\.id)

        guard newIDs != originalIDs else { return }

        var updates: [(caree: Caree, order: Int)] = []

        for (index, caree) in ownedCarees.enumerated() {
            if caree.listOrder != index {
                caree.listOrder = index
                updates.append((caree, index))
            }
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            let sharedCarees = cacheService.sharedCarees
            allCarees = ownedCarees + sharedCarees
        }

        reorderTask?.cancel()
        reorderTask = Task { [updates] in
            await persistReorderedCarees(updates)
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
            guard let importService = importService else {
                error = AppError.saveFailed("Import service not initialized")
                return
            }

            isImporting = true

            Task {
                do {
                    // Start accessing security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        throw AppError.invalidInput("Unable to access file")
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    try await importService.importFromJSON(at: url)

                    // Refresh UI
                    await refreshAllCarees()

                    await MainActor.run {
                        isImporting = false
                    }
                } catch {
                    await MainActor.run {
                        self.error = AppError.saveFailed("Import failed: \(error.localizedDescription)")
                        isImporting = false
                        importService.progress = .idle
                    }
                }
            }

        case .failure(let error):
            self.error = AppError.saveFailed("Failed to select file: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Helpers

    private func arraysEqualByID<T: AnyObject>(lhs: [T], rhs: [T]) -> Bool {
        func id(of obj: AnyObject) -> UUID? {
            if let c = obj as? Caree { return c.id }
            if let a = obj as? Activity { return a.id }
            if let t = obj as? ActivityType { return t.id }
            return nil
        }
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if id(of: l) != id(of: r) { return false }
        }
        return true
    }

    private func persistReorderedCarees(_ updates: [(caree: Caree, order: Int)]) async {
        guard !updates.isEmpty else { return }

        do {
            for update in updates {
                if Task.isCancelled { return }
                try await cloudKitService.updateCaree(
                    update.caree,
                    listOrder: update.order
                )
            }

            if Task.isCancelled { return }

            if let cacheService = cacheService {
                await cacheService.refreshPublishedProperties()
            }
        } catch {
            await MainActor.run {
                let template = NSLocalizedString(
                    "Failed to update caree order. %@",
                    comment: "Caree reorder failure message"
                )
                let message = String(format: template, error.localizedDescription)
                self.error = AppError.saveFailed(message)
            }

            await refreshAllCarees()
        }
    }
}

// MARK: - View Modifiers

#if os(iOS)
struct BackupRestoreSheets: ViewModifier {
    @Binding var showingExport: Bool
    let exportFileURL: URL?
    @Binding var showingImport: Bool
    @Binding var isImporting: Bool
    let importProgress: ImportProgress
    let handleImport: (Result<URL, Error>) -> Void
    @Binding var showingHelp: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingExport) {
                if let exportFileURL = exportFileURL {
                    ShareSheet(items: [exportFileURL])
                }
            }
            .fileImporter(
                isPresented: $showingImport,
                allowedContentTypes: [.json],
                onCompletion: handleImport
            )
            .sheet(isPresented: $isImporting) {
                ImportProgressView(progress: importProgress)
            }
            .sheet(isPresented: $showingHelp) {
                HelpView()
            }
    }
}
#else
struct BackupRestoreSheets: ViewModifier {
    @Binding var showingExport: Bool
    let exportFileURL: URL?
    @Binding var showingImport: Bool
    @Binding var isImporting: Bool
    let importProgress: ImportProgress
    let handleImport: (Result<URL, Error>) -> Void

    func body(content: Content) -> some View {
        content
    }
}
#endif

struct DataObservers: ViewModifier {
    let sharedRecordsService: CloudKitSharedRecordsService
    let cacheService: LocalCacheService?
    let cloudKitService: CloudKitDataService
    let importService: CareeImportService?
    let onError: (Error) -> Void
    let onDeletionProgress: (Bool, Double) -> Void
    let onImportProgress: (ImportProgress) -> Void
    let onUpdate: () -> Void

    private var myCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService = cacheService {
            return cacheService.$myCarees.eraseToAnyPublisher()
        } else {
            return Just([]).eraseToAnyPublisher()
        }
    }

    private var sharedCareesPublisher: AnyPublisher<[Caree], Never> {
        if let cacheService = cacheService {
            return cacheService.$sharedCarees.eraseToAnyPublisher()
        } else {
            return Just([]).eraseToAnyPublisher()
        }
    }

    func body(content: Content) -> some View {
        content
            .onReceive(sharedRecordsService.$error) { newError in
                if let newError = newError {
                    onError(newError)
                }
            }
            .onReceive(myCareesPublisher) { _ in
                onUpdate()
            }
            .onReceive(sharedCareesPublisher) { _ in
                onUpdate()
            }
            .onReceive(cloudKitService.$deletionProgress) { progress in
                onDeletionProgress(progress.isDeleting, progress.progress)
            }
            .modifier(ImportProgressObserver(
                importService: importService,
                onImportProgress: onImportProgress
            ))
    }
}

struct ImportProgressObserver: ViewModifier {
    let importService: CareeImportService?
    let onImportProgress: (ImportProgress) -> Void

    private var importProgressPublisher: AnyPublisher<ImportProgress, Never> {
        if let importService = importService {
            return importService.$progress.eraseToAnyPublisher()
        } else {
            return Just(.idle).eraseToAnyPublisher()
        }
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onReceive(importProgressPublisher) { progress in
                onImportProgress(progress)
            }
        #else
        content
        #endif
    }
}

#Preview {
    NavigationView {
        CareeListView()
    }
    .modelContainer(PreviewContainer.shared)
}
