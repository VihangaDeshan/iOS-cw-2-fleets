//
//  DriverFuelView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData

// MARK: - Driver Fuel View
struct DriverFuelView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var assignedVehicle: VehicleEntity?
    @State private var isLoading = false

    private var normalizedVehicleId: String {
        authViewModel.assignedVehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading Fuel Logs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let assignedVehicle {
                    FuelLogView(vehicle: assignedVehicle)
                } else {
                    ContentUnavailableView(
                        "No Vehicle Assigned",
                        systemImage: "fuelpump",
                        description: Text("Ask your manager to assign a vehicle to start fuel logging.")
                    )
                }
            }
            .navigationTitle("Fuel")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: normalizedVehicleId) {
            loadAssignedVehicle()
        }
    }

    private func loadAssignedVehicle() {
        isLoading = true
        defer { isLoading = false }

        guard let vehicleUUID = UUID(uuidString: normalizedVehicleId) else {
            assignedVehicle = nil
            return
        }

        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", vehicleUUID as CVarArg)

        assignedVehicle = try? context.fetch(request).first
    }
}

#Preview {
    DriverFuelView()
        .environmentObject(AuthViewModel())
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
