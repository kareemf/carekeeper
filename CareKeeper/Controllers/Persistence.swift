import CoreData
import Combine
import OSLog

class PersistenceController: ObservableObject {
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
    private static let authorName = "CareKeeper watchOS"
    private static let remoteDataImportAuthorName = "CareKeeper watchOS Data Import"
#else
    private static let authorName = "CareKeeper"
    private static let remoteDataImportAuthorName = "CareKeeper Data Import"
#endif

    let container: NSPersistentCloudKitContainer
    private var subscriptions = [AnyCancellable]()
    private lazy var historyRequestQueue = DispatchQueue(label: "history")

    private var lastHistoryToken: NSPersistentHistoryToken?

    private lazy var tokenFileURL: URL = {
        let url = NSPersistentCloudKitContainer.defaultDirectoryURL()
            .appendingPathComponent("CareKeeper", isDirectory: true)
        do {
            try FileManager.default
                .createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: nil)
        } catch {
            logError("Error initializing history token", error: error)
        }
        return url.appendingPathComponent("token.data", isDirectory: false)
    }()

    private func logError(_ message: String, error: Error) {
        logger.error("\(message, privacy: .public): \(error)")
        errorHandling.handle(error: error, description: message)
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "CareKeeperCoreData")

        let persistentStoreDescription = container.persistentStoreDescriptions.first!

        if inMemory {
            persistentStoreDescription.url = URL(fileURLWithPath: "/dev/null")
        } else {
            do {
                try container.viewContext.setQueryGenerationFrom(.current)
            } catch {
                logError("Error setting query generation", error: error)
            }
        }

        // Generate notifications on change
        persistentStoreDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        // Persist change history
        persistentStoreDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey)

        container.loadPersistentStores(completionHandler: { (_, error) in
            if let error = error as NSError? {
                self.logError("Error loading persistent stores", error: error)
            }
        })

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.transactionAuthor = PersistenceController.authorName

        // Sub to notifications
        loadHistoryToken()

        NotificationCenter.default
            .publisher(for: .NSPersistentStoreRemoteChange)
            .sink { [self] in
                self.processRemoteStoreChange($0)
            }
            .store(in: &subscriptions)

    }

    func processRemoteStoreChange(_ notification: Notification) {
        print("Store Notification", notification)

        historyRequestQueue.async {
            let backgroundContext = self.container.newBackgroundContext()

            backgroundContext.performAndWait {
                let request = NSPersistentHistoryChangeRequest
                    .fetchHistory(after: self.lastHistoryToken)

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
                        self.storeHistoryToken(newToken)
                    }
                } catch {
                    self.logError("Error processing remote notifications", error: error)
                }
            }
        }
    }

    private func storeHistoryToken(_ token: NSPersistentHistoryToken) {
        do {
            let data = try NSKeyedArchiver
                .archivedData(withRootObject: token, requiringSecureCoding: true)
            try data.write(to: tokenFileURL)
            lastHistoryToken = token
        } catch {
            logError("Error writing history token", error: error)
        }
    }

    private func loadHistoryToken() {
        do {
            let tokenData = try Data(contentsOf: tokenFileURL)
            lastHistoryToken = try NSKeyedUnarchiver
                .unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: tokenData)
        } catch {
            logError("Error retrieving history token", error: error)
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
}
