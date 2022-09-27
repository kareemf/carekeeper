//
//  CareKeeperCoreDataApp.swift
//  CareKeeperCoreData
//
//  Created by Kareem Francis on 9/27/22.
//

import SwiftUI

@main
struct CareKeeperCoreDataApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
