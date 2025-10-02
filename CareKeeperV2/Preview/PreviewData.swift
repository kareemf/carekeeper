import Foundation
import SwiftData
import UIKit

@MainActor
struct PreviewData {
    
    static func addSampleData(to context: ModelContext) {
        // Create sample carees
        let babyCaree = Caree(name: "Baby Emma", listOrder: 0)
        let petCaree = Caree(name: "Max (Dog)", listOrder: 1)
        
        context.insert(babyCaree)
        context.insert(petCaree)
        
        // Create activity types for baby
        let feeding = ActivityType(
            name: "Feeding",
            icon: "🍼",
            hasQuantity: true,
            quantityUnit: "oz",
            hasLocation: false,
            listOrder: 0,
            caree: babyCaree
        )
        
        let diaper = ActivityType(
            name: "Diaper Change",
            icon: "👶",
            hasQuantity: false,
            hasLocation: false,
            listOrder: 1,
            caree: babyCaree
        )
        
        let nap = ActivityType(
            name: "Nap",
            icon: "😴",
            hasQuantity: true,
            quantityUnit: "minutes",
            hasLocation: false,
            listOrder: 2,
            caree: babyCaree
        )
        
        context.insert(feeding)
        context.insert(diaper)
        context.insert(nap)
        
        // Create activity types for pet
        let walk = ActivityType(
            name: "Walk",
            icon: "🚶",
            hasQuantity: true,
            quantityUnit: "minutes",
            hasLocation: true,
            listOrder: 0,
            caree: petCaree
        )
        
        let petFeeding = ActivityType(
            name: "Feeding",
            icon: "🥣",
            hasQuantity: true,
            quantityUnit: "cups",
            hasLocation: false,
            listOrder: 1,
            caree: petCaree
        )
        
        context.insert(walk)
        context.insert(petFeeding)
        
        // Create sample activities
        let now = Date()
        let calendar = Calendar.current
        
        // Recent feeding
        let recentFeeding = Activity(
            dateTime: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
            notes: "Had a good feeding session",
            quantity: 4.0,
            activityType: feeding,
            caree: babyCaree
        )
        
        // Recent diaper change
        let recentDiaper = Activity(
            dateTime: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
            notes: "Wet diaper",
            activityType: diaper,
            caree: babyCaree
        )
        
        // Dog walk with location
        let dogWalk = Activity(
            dateTime: calendar.date(byAdding: .hour, value: -3, to: now) ?? now,
            notes: "Great walk in the park",
            quantity: 30.0,
            latitude: 37.7749,
            longitude: -122.4194,
            activityType: walk,
            caree: petCaree
        )
        
        context.insert(recentFeeding)
        context.insert(recentDiaper)
        context.insert(dogWalk)
        
        try? context.save()
    }
    
    // Static sample data for individual previews
    static let sampleCaree: Caree = {
        Caree(name: "Sample Caree")
    }()
    
    static let sampleCareeWithImage: Caree = {
        let caree = Caree(name: "Caree with Photo")
        // In a real app, you'd add actual image data here
        caree.image = createSampleImageData()
        return caree
    }()
    
    static let sampleCareeWithActivities: Caree = {
        let caree = Caree(name: "Active Caree")
        
        let activityType = ActivityType(
            name: "Sample Activity",
            icon: "🍼",
            hasQuantity: true,
            quantityUnit: "oz",
            caree: caree
        )
        
        let activity = Activity(
            notes: "Sample activity note",
            quantity: 5.0,
            activityType: activityType,
            caree: caree
        )
        
        return caree
    }()
    
    static let sampleActivityType: ActivityType = {
        let caree = Caree(name: "Sample Caree")
        return ActivityType(
            name: "Feeding",
            icon: "🍼",
            hasQuantity: true,
            quantityUnit: "oz",
            caree: caree
        )
    }()
    
    static let sampleActivity: Activity = {
        let caree = Caree(name: "Sample Caree")
        let activityType = ActivityType(
            name: "Feeding",
            icon: "🍼",
            hasQuantity: true,
            quantityUnit: "oz",
            caree: caree
        )
        
        return Activity(
            notes: "Sample feeding session",
            quantity: 4.0,
            activityType: activityType,
            caree: caree
        )
    }()
    
    private static func createSampleImageData() -> Data? {
        // Create a simple colored circle as sample image data
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        
        return image.pngData()
    }
}