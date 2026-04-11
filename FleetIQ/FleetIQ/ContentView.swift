//
//  ContentView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-11.
//

import SwiftUI
import CoreData

struct ContentView: View {
    // MARK: - Body

    var body: some View {
        Color.clear
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
