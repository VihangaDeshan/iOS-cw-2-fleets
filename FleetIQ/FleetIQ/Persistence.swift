//
//  Persistence.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-11.
//

import CoreData

struct PersistenceController {
    // MARK: - Shared Instances
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        return PersistenceController(inMemory: true)
    }()

    // MARK: - Properties
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Initializer
    /// Creates the FleetIQ persistent container.
    /// - Parameter inMemory: Uses an in-memory store when true, useful for tests and previews.

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "FleetIQ")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save
    /// Saves pending changes in the main view context.
    func save() {
        guard viewContext.hasChanges else {
            return
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}
