//
//  ManagerSettingsView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Manager Settings View
struct ManagerSettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("isUnlocked") private var isUnlocked = false

    // Computed initials for the avatar
    private var managerInitials: String {
        let name = authViewModel.currentUserName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "M" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Profile Header
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.navyPrimary, Color.navySecondary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)

                            Text(managerInitials)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(authViewModel.currentUserName.isEmpty ? "Manager" : authViewModel.currentUserName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(authViewModel.userRole.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            NavigationLink {
                                UserProfileView()
                                    .environmentObject(authViewModel)
                            } label: {
                                Text("View Profile")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.navyPrimary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color(.systemBackground))

                // MARK: Account
                Section {
                    infoRow(
                        icon: "building.2.fill",
                        iconColor: .navyPrimary,
                        title: "Fleet ID",
                        value: authViewModel.fleetId.isEmpty ? "—" : authViewModel.fleetId
                    )
                    infoRow(
                        icon: "person.circle.fill",
                        iconColor: Color(hex: "5856D6"),
                        title: "User ID",
                        value: authViewModel.currentUID.isEmpty ? "—" : String(authViewModel.currentUID.prefix(12)) + "…"
                    )
                } header: {
                    sectionHeader("ACCOUNT")
                }

                // MARK: Security
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "34C759").opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "faceid")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(hex: "34C759"))
                        }

                        Toggle("Face ID Lock", isOn: $faceIDEnabled)
                            .font(.body)
                            .onChange(of: faceIDEnabled) { _, enabled in
                                if !enabled {
                                    isUnlocked = true
                                }
                            }
                    }
                } header: {
                    sectionHeader("SECURITY")
                }

                // MARK: Sign Out
                Section {
                    Button(role: .destructive) {
                        authViewModel.signOut()
                    } label: {
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.statusOverdue)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    private func infoRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .foregroundColor(.primary)

            Spacer()

            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
