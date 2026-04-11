//
//  FleetIQApp.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-11.
//

import SwiftUI
import CoreData
#if canImport(Firebase)
import Firebase
#elseif canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@main
struct FleetIQApp: App {
    // MARK: - Properties
    let persistenceController = PersistenceController.shared

    // MARK: - Initializer
    /// Configures Firebase services during app launch.
    init() {
        configureFirebaseIfAvailable()
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }

    // MARK: - Private Methods
    /// Configures Firebase App and enables Firestore offline persistence when Firebase SDKs are available.
    private func configureFirebaseIfAvailable() {
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
#endif

#if canImport(FirebaseFirestore)
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        Firestore.firestore().settings = settings
#endif
    }
}
