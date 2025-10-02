// Temporary Core Data entities for v1 compatibility
// These will be removed once we fully migrate to v2 SwiftData

import Foundation
import CoreData

// Mock Core Data entities to satisfy v1 Persistence.swift
// These are not actually used - just here for compilation

@objc(Caree)
public class Caree: NSManagedObject {
    @NSManaged public var dateCreated: Date?
    @NSManaged public var name: String?
    @NSManaged public var activities: NSSet?
    @NSManaged public var behaviors: NSSet?
    @NSManaged public var photo: Photo?
}

@objc(Photo)
public class Photo: NSManagedObject {
    @NSManaged public var data: Data?
    @NSManaged public var caree: Caree?
}

@objc(Behavior)
public class Behavior: NSManagedObject {
    @NSManaged public var dateCreated: Date?
    @NSManaged public var name: String?
    @NSManaged public var icon: String?
    @NSManaged public var enableLocations: Bool
    @NSManaged public var caree: Caree?
    @NSManaged public var activities: NSSet?
}

@objc(Activity)  
public class Activity: NSManagedObject {
    @NSManaged public var dateCreated: Date?
    @NSManaged public var when: Date?
    @NSManaged public var caree: Caree?
    @NSManaged public var behavior: Behavior?
}