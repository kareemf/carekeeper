//
//  CareKeeperWatchApp.swift
//  CareKeeperWatch Watch App
//
//  Created by Kareem Francis on 9/27/22.
//

import SwiftUI

@main
struct CareKeeperWatch_Watch_AppApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
    
    
}
