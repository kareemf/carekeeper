import CoreData
import CloudKit
import Combine
import OSLog

class PersistenceController: NSObject, ObservableObject {
    let gCloudKitContainerIdentifier = "iCloud.com.kareemf.CareKeeperCK"
    
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // swiftlint:disable:next identifier_name
        for i in 0..<10 {
            let caree = Caree(context: viewContext)
            caree.dateCreated = Date()
            caree.name = "Caree \(i)"

            let behavior = Behavior(context: viewContext)
            behavior.dateCreated = Date()
            behavior.name = "Behavior"
            behavior.caree = caree
            behavior.icon = "🏃🏾"
            behavior.enableLocations = true

            let behavior2 = Behavior(context: viewContext)
            behavior2.dateCreated = Date()
            behavior2.name = "Behavior"
            behavior2.caree = caree

            let activity = Activity(context: viewContext)
            activity.dateCreated = Date()
            activity.when = activity.dateCreated
            activity.caree = caree
            activity.behavior = behavior
        }

        do {
            try viewContext.save()
        } catch {
            let logger = Logger(subsystem: "com.kareemf.carekeeper", category: "persistence")
            let nsError = error as NSError

            logger.error("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return result
    }()

    let logger = Logger(subsystem: "com.kareemf.carekeeper", category: "persistence")

    @Published var errorHandling = ErrorHandling()

#if os(watchOS)
    static let authorName = "CareKeeper watchOS"
    private static let remoteDataImportAuthorName = "CareKeeper watchOS Data Import"
#else
    static let authorName = "CareKeeper"
    private static let remoteDataImportAuthorName = "CareKeeper Data Import"
#endif

    var container: NSPersistentCloudKitContainer
    private var subscriptions = [AnyCancellable]()
    private lazy var historyRequestQueue = DispatchQueue(label: "history")
    
    func baseUrl() throws -> URL {
        let url = NSPersistentCloudKitContainer.defaultDirectoryURL()
            .appendingPathComponent("CareKeeper", isDirectory: true)
        do {
            try FileManager.default
                .createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: nil)
            
            return url
        } catch {
            throw error
        }
    }

    
    lazy var cloudKitContainer: CKContainer = {
        return CKContainer(identifier: gCloudKitContainerIdentifier)
    }()

    func logError(_ message: String, error: Error) {
        logger.error("\(message, privacy: .public): \(error)")
        errorHandling.handle(error: error, description: message)
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "CareKeeperCoreData")
        
        super.init()
        
        let (privateStoreFolderURL, sharedStoreFolderURL) = loadStoreURLs()
        
        guard let privateStoreDescription = container.persistentStoreDescriptions.first else {
            logger.error("Error retrieving a persistent store description")
            return
        }

        if inMemory {
            privateStoreDescription.url = URL(fileURLWithPath: "/dev/null")
        } else {
            do {
                privateStoreDescription.url = privateStoreFolderURL
                try container.viewContext.setQueryGenerationFrom(.current)
            } catch {
                logError("Error setting query generation", error: error)
            }
        }

        // Generate notifications on change
        privateStoreDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        // Persist change history
        privateStoreDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey)
        
        // Start Shared DB setup
        guard let sharedStoreDescription = privateStoreDescription.copy() as? NSPersistentStoreDescription else {
            //TODO: error handling
            fatalError("#\(#function): Copying the private store description returned an unexpected value.")
        }
                
        sharedStoreDescription.url = inMemory ? URL(fileURLWithPath: "/dev/null") : sharedStoreFolderURL
        
        let sharedStoreOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: gCloudKitContainerIdentifier)
        sharedStoreOptions.databaseScope = .shared
        sharedStoreDescription.cloudKitContainerOptions = sharedStoreOptions
        
        container.persistentStoreDescriptions.append(sharedStoreDescription)
        // End Shared DB setup

        container.loadPersistentStores(completionHandler: { [self] (loadedStoreDescription, error) in
            if let error = error as NSError? {
                self.logError("Error loading persistent stores", error: error)
                return
            }
            
            guard let cloudKitContainerOptions = loadedStoreDescription.cloudKitContainerOptions else {
                return
            }
            
            if cloudKitContainerOptions.databaseScope == .private {
                self._privatePersistentStore = container.persistentStoreCoordinator.persistentStore(for: loadedStoreDescription.url!)
            } else if cloudKitContainerOptions.databaseScope  == .shared {
                self._sharedPersistentStore = container.persistentStoreCoordinator.persistentStore(for: loadedStoreDescription.url!)
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.transactionAuthor = PersistenceController.authorName

        // Sub to notifications
        NotificationCenter.default
            .publisher(for: .NSPersistentStoreRemoteChange)
            .sink { [self] in
                self.processRemoteStoreChange($0)
            }
            .store(in: &subscriptions)
    }
    
    private func loadStoreURLs() -> (URL?, URL?) {
        do {
            let storeFolderURL = try baseUrl().appendingPathComponent("CoreDataStores", isDirectory: true)
            let privateStoreFolderURL = storeFolderURL.appendingPathComponent("Private", isDirectory: true)
            let sharedStoreFolderURL = storeFolderURL.appendingPathComponent("Shared", isDirectory: true)
            
            let fileManager = FileManager.default
            
            for folderURL in [privateStoreFolderURL, sharedStoreFolderURL] where !fileManager.fileExists(atPath: folderURL.path) {
                do {
                    try fileManager
                        .createDirectory(
                            at: folderURL,
                            withIntermediateDirectories: true,
                            attributes: nil
                        )
                } catch {
                    logError("Error initializing store folder ", error: error)
                    return  (nil, nil)
                }
            }
            
            return (
                privateStoreFolderURL.appendingPathComponent("private.sqlite"),
                sharedStoreFolderURL.appendingPathComponent("shared.sqlite")
            )

        } catch {
            logError("Error initializing base folder for stores", error: error)
        }
        return  (nil, nil)
    }
    

    func processRemoteStoreChange(_ notification: Notification) {
        print("Store Notification", notification)
        
        guard let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String,
              [privatePersistentStore.identifier, sharedPersistentStore.identifier].contains(storeUUID) else {
            print("\(#function): Ignore a store remote Change notification because of no valid storeUUID.")
            return
        }
        
        let lastHistoryToken = loadHistoryToken(storeUUID: storeUUID)

        historyRequestQueue.async {
            let backgroundContext = self.container.newBackgroundContext()

            backgroundContext.performAndWait {
                let request = NSPersistentHistoryChangeRequest
                    .fetchHistory(after: lastHistoryToken)

                do {
                    let result = try backgroundContext.execute(request) as? NSPersistentHistoryResult

                    guard
                        let transactions = result?.result as? [NSPersistentHistoryTransaction],
                        !transactions.isEmpty
                    else {
                        return
                    }

                    print("History transactions", transactions)

                    self.mergeChanges(from: transactions)

                    if let newToken = transactions.last?.token {
                        self.storeHistoryToken(token: newToken, storeUUID: storeUUID)
                    }
                } catch {
                    self.logError("Error processing remote notifications", error: error)
                }
            }
        }
    }

    private func mergeChanges(from transactions: [NSPersistentHistoryTransaction]) {
        let context = container.viewContext

        context.perform {
            transactions.forEach { transaction in
                guard let userInfo = transaction.objectIDNotification().userInfo else {
                    return
                }

                NSManagedObjectContext
                    .mergeChanges(fromRemoteContextSave: userInfo, into: [context])
            }
        }
    }
    
    private var _privatePersistentStore: NSPersistentStore?
    var privatePersistentStore: NSPersistentStore {
        return _privatePersistentStore!
    }
    
    private var _sharedPersistentStore: NSPersistentStore?
    var sharedPersistentStore: NSPersistentStore {
        return _sharedPersistentStore!
    }
}
