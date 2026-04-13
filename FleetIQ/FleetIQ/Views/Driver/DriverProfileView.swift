//
//  DriverProfileView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI

// MARK: - Driver Profile View
struct DriverProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("isUnlocked") private var isUnlocked = false

    private var initials: String {
        let trimmedName = authViewModel.currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "DR"
        }

        let parts = trimmedName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }

        return String(trimmedName.prefix(2)).uppercased()
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.driverGreen)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Text(initials)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(authViewModel.currentUserName.isEmpty ? "Driver" : authViewModel.currentUserName)
                            .font(.headline)

                        Text("Fleet: \(authViewModel.fleetId.isEmpty ? "-" : authViewModel.fleetId)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("ACCOUNT") {
                infoRow(title: "Role", value: authViewModel.userRole.capitalized)
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

            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#Preview {
    NavigationStack {
        DriverProfileView()
            .environmentObject(AuthViewModel())
    }
}
