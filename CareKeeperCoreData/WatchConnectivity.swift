import Foundation
import WatchConnectivity
import CoreData

struct NotificationMessage: Identifiable {
    let id = UUID()
    let text: String
}
//
class WatchConnectivityController: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchConnectivityController()
//
//    public var onDataRecived: (([Caree]) -> Void)? = nil
//
    enum ConnectivityKey: String {
        case timeStamp = "timeStamp"
        case message = "message"
        case messageType = "messageType"
        case syncInit = "syncInit"
        case syncReply = "syncReply"
        case syncDoneApp = "syncDoneApp"
        case syncDoneWatch = "syncDoneWatch"
    }
//
//    @Published var data: [Caree] = []
////    @Published var userInfoSent: [String: Any]? = nil
////    @Published var userInfoRecived: [String: Any]? = nil
    @Published var messageSent: [String: Any]? = nil
    @Published var messageRecived: [String: Any]? = nil
    @Published var notificationMessageRecived: NotificationMessage? = nil
    
    override init() {
        super.init()

        #if !os(watchOS)
        guard WCSession.isSupported() else {
            return
        }
        #endif

        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
    }
//
////    func session(
////        _ session: WCSession,
////        didReceiveUserInfo userInfo: [String: Any] = [:]
////    ) {
////        userInfoRecived = userInfo
////
////        let key = ConnectivityKey.timeStamp.rawValue
////
////        guard let data = userInfo[key] as? [Caree] else {
////            return
////        }
////
////        self.data = data
////    }
//
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any]) {
//
            DispatchQueue.main.async { [weak self] in
                self?.messageRecived = message
                print("Watch: message recived", message)
//
                guard let messageType = message[ConnectivityKey.messageType.rawValue] as? String else {
                    print("Watch: unrecognized message type in", message)
                    return
                }
                
                switch messageType {
                case ConnectivityKey.syncInit.rawValue:
                    print("Watch: syncInit")
                    if let notification = message[ConnectivityKey.message.rawValue] as? Notification {
                        PersistenceController.shared.container.viewContext.mergeChanges(fromContextDidSave: notification)
                    }
                    
                default:
                    print("Watch: fell into default for messageType", messageType)
                }
//
//                if let notificationText = message[ConnectivityKey.message.rawValue] as? Data {
////                    TODO: error handling
//                    let carees = try! JSONDecoder().decode([Caree].self, from: notificationText)
//                    self?.data = carees
//                    self?.notificationMessageRecived = NotificationMessage(text: "Updated data")
//                    if ((self?.onDataRecived) != nil) {
//                        self?.onDataRecived!(carees)
//                    }
//                }
//
            }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
    
    public func send(context: NSManagedObjectContext) {
        guard WCSession.default.activationState == .activated else {
            print("Watch: session inactive")
            self.notificationMessageRecived = NotificationMessage(text: "Watch session inactive")
            return
        }

        #if !os(watchOS)
        guard WCSession.default.isWatchAppInstalled else {
            print("Watch: isWatchAppInstalled false")
            self.notificationMessageRecived = NotificationMessage(text: "Watch app not installed")
            return
        }
        #else
        guard WCSession.default.isCompanionAppInstalled else {
            print("Watch: isCompanionAppInstalled false")
            self.notificationMessageRecived = NotificationMessage(text: "Companion app not installed")
            return
        }
        #endif

        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .medium
        let timeStamp = dateFormatter.string(from: Date())
        
        //        TODO: error handling
//        let json = try! JSONEncoder().encode(notification.userInfo)
        
//        print(notification.userInfo)
        
    

        messageSent = [
            ConnectivityKey.timeStamp.rawValue: timeStamp,
            ConnectivityKey.messageType.rawValue: ConnectivityKey.syncInit.rawValue,
            "insertedObjects": context.insertedObjects.map({ obj in
                obj.entity.attributesByName
            }),
            "updatedObjects": context.updatedObjects.map({ obj in
                obj.entity.attributesByName
            }),
            "deletedObjects": context.deletedObjects.map({ obj in
                obj.entity.attributesByName
            }),
        ]

        WCSession.default.sendMessage(messageSent!, replyHandler: nil, errorHandler: { error in
            DispatchQueue.main.async { [weak self] in
                print("Watch: send: Cannot send message: \(String(describing: error))")
                self?.notificationMessageRecived = NotificationMessage(text: "Cannot send message: \(String(describing: error))")
            }
        })
        
//        do{
//            try WCSession.default.updateApplicationContext(messageSent!)
//        } catch {
//            print("Watch updateApplicationContext error", error)
//        }

        //        TODO: transferUserInfo for non sims
        //        userInfoSent = [ConnectivityKey.timeStamp.rawValue: timeStamp, "carees": carees]
        //        WCSession.default.transferUserInfo(userInfo)

    }
}
