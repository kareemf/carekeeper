#  Scraps

```swift
    private func serializeEntities(_ objects: Set<NSManagedObject>) -> [[String : Any]] {
        return objects.map({ serializeEntity($0) })
    }
    
    private func serializeEntity(_ obj: NSManagedObject) -> [String : Any] {
        var kv: [String : Any] = [:]
        
        kv["id"] = "\((obj as! any Identifiable).id)"
        kv["objectID"] = "\(obj.objectID)"
//        NSURL(obj.objectID).
        kv["entity"] = obj.entity.name!
        
        obj.entity.attributesByName.keys.forEach({key in
            let propDescriptor = obj.entity.attributesByName[key]
            
            if propDescriptor?.type == .date {
                kv[key] = getStringFromDate(date: obj.value(forKey: key) as! Date)
            } else {
                kv[key] = "\(obj.value(forKey: key))"
            }
        })
        
        var relationships: [String: [String]] = [:]
        obj.entity.relationshipsByName.keys.forEach({key in
            
            relationships[key] = obj.objectIDs(forRelationshipNamed: key).map({"\($0)"})
            
        })
        kv["relationships"] = relationships
        
        return kv
    }
    
    private func deserializeEntities(_ kvPairs: [[String : Any]], context: NSManagedObjectContext) -> Set<NSManagedObject> {
        let objects: Set<NSManagedObject> = Set()
        
        kvPairs.map({kvPair in
            var managedObject: NSManagedObject
            print("kvPair", kvPair)
            
            
            // TODO: how to lookup from string
            switch (kvPair["entity"] as! String) {
            case "Caree":
                managedObject = Caree()
            case "Behavior":
                managedObject = Behavior()
            case "Activity":
                managedObject = Activity()
            default:
                fatalError("deserializeEntities: unknown entity type")
            }
            
            managedObject.entity.attributesByName.forEach({propName, propDescriptor in
                let _value = kvPair[propName] as! String
                
                if _value == "nil" {
                    return
                }
                
                print("set", propName, "to", _value)
                
                if propDescriptor.type == .date {
                    managedObject.setValue(getDate(_value), forKey: propName)
                }
                
                managedObject.setValue(_value, forKey: propName)
            })
            
            //TODO: relationships
        })
        
        return objects
    }
    
    func getDate(_ from: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale.current
        
        return dateFormatter.date(from: from)
    }
    
    func getStringFromDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        
        return dateFormatter.string(from: date)
    }
    
    private func serializeTransactions(context: NSManagedObjectContext, transactions: [NSPersistentHistoryTransaction]) -> ([[String: Any]], [[String: Any]], [([String: Any], [String])]) {
        var insertedObjects: [[String: Any]] = []
        var deletedObjects: [[String: Any]] = []
        var updatedObjects: [([String: Any], [String])] = []
        
        transactions.forEach({transaction in
            transaction.changes?.forEach({ change in
                let changeType = change.changeType
                let changedObjectID = change.changedObjectID
                
                do {
                    let object = try context.existingObject(
                        with: change.changedObjectID
                    )
                    
                    let foo = serializeEntity(object)
                    
                    if changeType == .insert {
                        insertedObjects.append(foo)
                    } else if changeType == .delete {
                        deletedObjects.append(foo)
                    } else {
                        var updatedProperties: [String] = []
                        
                        change.updatedProperties?.forEach({prop in
                            updatedProperties.append(prop.name)
                        })
                        
                        updatedObjects.append((foo, updatedProperties))
                    }
                    
                } catch {
                    print("Persistence: failed", error)
                }
            })
        })
        
        return (insertedObjects, deletedObjects, updatedObjects)
    }
    
    public func send(context: NSManagedObjectContext, transactions: [NSPersistentHistoryTransaction]) {
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
        let timeStamp = getStringFromDate(date: Date())
        
        //        TODO: error handling
        //        let json = try! JSONEncoder().encode(notification.userInfo)
        
        //        print(notification.userInfo)
        let serializedTransactions = serializeTransactions(context: context, transactions: transactions)
        messageSent = [
            ConnectivityKey.timeStamp.rawValue: timeStamp,
            ConnectivityKey.messageType.rawValue: ConnectivityKey.syncInit.rawValue,
            "insertedObjects": serializedTransactions.0,
            "updatedObjects": serializedTransactions.2,
            "deletedObjects": serializedTransactions.1
            
        ]
        
        deserializeEntities(serializedTransactions.0, context: context)
        
        print("Watch: sendMessage:", String(describing: messageSent))
        WCSession.default.sendMessage(messageSent!, replyHandler: nil, errorHandler: { error in
            DispatchQueue.main.async { [weak self] in
                print("Watch: sendMessage: Cannot send message: \(String(describing: error))")
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
```

