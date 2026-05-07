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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Profile Header
                VStack(spacing: 12) {
                    Text(initials)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.navyPrimary)
                        .clipShape(Circle())
                        .shadow(color: Color.navyPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    VStack(spacing: 4) {
                        Text(authViewModel.currentUserName.isEmpty ? "Driver" : authViewModel.currentUserName)
                            .font(.title3.weight(.bold))
                        
                        Text("Fleet ID: \(authViewModel.fleetId.isEmpty ? "-" : authViewModel.fleetId)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

                // Account Section
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("ACCOUNT")
                    
                    VStack(spacing: 0) {
                        infoRow(title: "Role", value: authViewModel.userRole.capitalized, icon: "person.badge.shield.fill")
                        Divider().padding(.leading, 44)
                        infoRow(title: "Driver ID", value: authViewModel.currentUID, icon: "number")
                        Divider().padding(.leading, 44)
                        infoRow(title: "Vehicle ID", value: authViewModel.assignedVehicleId, icon: "car.fill")
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
                }

                // Security Section
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("SECURITY")
                    
                    HStack(spacing: 12) {
                        Image(systemName: "faceid")
                            .foregroundColor(.statusActive)
                            .frame(width: 32, height: 32)
                            .background(Color.statusActive.opacity(0.1))
                            .clipShape(Circle())
                        
                        Toggle("Face ID Lock", isOn: $faceIDEnabled)
                            .font(.subheadline.weight(.medium))
                            .onChange(of: faceIDEnabled) { _, enabled in
                                if !enabled { isUnlocked = true }
                            }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
                }

                // Sign Out
                Button {
                    authViewModel.signOut()
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.square.fill")
                        Text("Sign Out")
                            .font(.headline)
                    }
                    .foregroundColor(.statusOverdue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.statusOverdue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.navyPrimary)
                .frame(width: 32, height: 32)
                .background(Color.navyPrimary.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(14)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }
}

#Preview {
    NavigationStack {
        DriverProfileView()
            .environmentObject(AuthViewModel())
    }
}
