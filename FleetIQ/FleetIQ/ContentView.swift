//
//  ContentView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-11.
//

import SwiftUI
import CoreData

struct ContentView: View {
    // MARK: - Stored Properties
    @State private var selectedCanvasScreen: CanvasScreen = .onboarding

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Canvas Screen", selection: $selectedCanvasScreen) {
                    ForEach(CanvasScreen.allCases, id: \.self) { screen in
                        Text(screen.title)
                            .tag(screen)
                    }
                }
                .pickerStyle(.segmented)

                screenContent(selectedCanvasScreen)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(16)
            .navigationTitle("FleetIQ Canvas")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Private Methods
    /// Builds the selected canvas screen content.
    /// - Parameter screen: Selected canvas screen.
    /// - Returns: Corresponding screen view.
    @ViewBuilder
    private func screenContent(_ screen: CanvasScreen) -> some View {
        switch screen {
        case .onboarding:
            OnboardingView()
        case .faceLock:
            LockScreenView()
        case .roleSelection:
            RoleSelectionView()
        }
    }
}

// MARK: - Canvas Screen
private enum CanvasScreen: CaseIterable {
    case onboarding
    case faceLock
    case roleSelection

    // MARK: - Computed Properties
    var title: String {
        switch self {
        case .onboarding:
            return "Onboarding"
        case .faceLock:
            return "Face Lock"
        case .roleSelection:
            return "Role"
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
