import Foundation
import CoreData

extension PersistenceController {
    private func tokenFileURL(_ storeUUID: String) -> URL? {
        do {
            return try baseUrl().appendingPathComponent("token-\(storeUUID).data", isDirectory: false)
        } catch {
            logError("Error initializing history token", error: error)
            return nil
        }
    }
    
    func storeHistoryToken(token: NSPersistentHistoryToken, storeUUID: String) {
        do {
            let data = try NSKeyedArchiver
                .archivedData(withRootObject: token, requiringSecureCoding: true)
            
            guard let url = tokenFileURL(storeUUID) else {
                //                TODO: error handling
                return
            }
            
            try data.write(to: url)
        } catch {
            logError("Error writing history token", error: error)
        }
    }
    
    func loadHistoryToken(storeUUID: String) -> NSPersistentHistoryToken? {
        do {
            guard let url = tokenFileURL(storeUUID) else {
                //                TODO: error handling
                return nil
            }
            
            let tokenData = try Data(contentsOf: url)
            return try NSKeyedUnarchiver
                .unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: tokenData)
        } catch {
            logger.error("Error initializing history token. Probably benign: \(error)")
            return nil
        }
    }
}
