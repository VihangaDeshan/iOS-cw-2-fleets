//
//  DriverSettingsView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI

// MARK: - Driver Settings View
struct DriverSettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("isUnlocked") private var isUnlocked = false

    var body: some View {
        NavigationStack {
            List {
                Section("ACCOUNT") {
                    infoRow(title: "Role", value: authViewModel.userRole.capitalized)
                    infoRow(title: "Fleet ID", value: authViewModel.fleetId)
                    infoRow(title: "Driver ID", value: authViewModel.currentUID)
                    infoRow(title: "Assigned Vehicle", value: authViewModel.assignedVehicleId)
                }

                Section("SECURITY") {
                    Toggle("Enable Face ID Lock", isOn: $faceIDEnabled)
                        .onChange(of: faceIDEnabled) { _, enabled in
                            if !enabled {
                                isUnlocked = true
                            }
                        }
                }

                Section("ABOUT") {
                    infoRow(title: "App", value: "FleetIQ")
                    infoRow(title: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }

                Section {
                    Button(role: .destructive) {
                        authViewModel.signOut()
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#Preview {
    DriverSettingsView()
        .environmentObject(AuthViewModel())
}
