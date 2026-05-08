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

    // Security
    @AppStorage("faceIDEnabled")     private var faceIDEnabled    = false
    @AppStorage("isUnlocked")        private var isUnlocked       = false
    @AppStorage("lockOnBackground")  private var lockOnBackground = true

    // Notifications
    @AppStorage("notifyExpiryWarnings") private var notifyExpiryWarnings = true
    @AppStorage("notifyFaultUpdates")   private var notifyFaultUpdates   = true

    // MARK: - Initials
    private var driverInitials: String {
        let name = authViewModel.currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "DR" }
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
                    NavigationLink(destination: DriverProfileView().environmentObject(authViewModel)) {
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
                                    .frame(width: 54, height: 54)
                                Text(driverInitials)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(authViewModel.currentUserName.isEmpty ? "Driver" : authViewModel.currentUserName)
                                    .font(.headline.weight(.semibold))
                                Text("Driver · \(authViewModel.fleetId.isEmpty ? "No fleet" : authViewModel.fleetId)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // MARK: Account
                Section {
                    infoRow(icon: "person.badge.shield.fill", iconColor: Color.navyPrimary,    label: "Role",    value: authViewModel.userRole.capitalized)
                    infoRow(icon: "building.2.fill",          iconColor: Color(hex: "5856D6"),  label: "Fleet ID", value: authViewModel.fleetId.isEmpty ? "—" : authViewModel.fleetId)
                    infoRow(icon: "car.fill",                 iconColor: Color.statusDueSoon,   label: "Vehicle",
                            value: authViewModel.assignedVehicleId.isEmpty ? "Not assigned" : String(authViewModel.assignedVehicleId.prefix(12)) + "…")
                } header: {
                    Text("Account")
                }

                // MARK: Security
                Section {
                    Toggle(isOn: $faceIDEnabled) {
                        Label {
                            Text("Face ID Lock")
                        } icon: {
                            iconCell("faceid", color: Color(hex: "34C759"))
                        }
                    }
                    .onChange(of: faceIDEnabled) { _, enabled in
                        if !enabled { isUnlocked = true }
                    }

                    Toggle(isOn: $lockOnBackground) {
                        Label {
                            Text("Lock on Background")
                        } icon: {
                            iconCell("lock.fill", color: Color(hex: "FF9500"))
                        }
                    }
                    .disabled(!faceIDEnabled)

                    NavigationLink(destination: AccessibilitySettingsView()) {
                        Label {
                            Text("Accessibility")
                        } icon: {
                            iconCell("accessibility", color: Color(hex: "007AFF"))
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("\"Lock on Background\" re-locks the app with Face ID each time it moves to the background. Requires Face ID Lock to be enabled.")
                }

                // MARK: Notifications
                Section {
                    Toggle(isOn: $notifyExpiryWarnings) {
                        Label {
                            Text("Document Expiry Warnings")
                        } icon: {
                            iconCell("doc.badge.clock.fill", color: Color(hex: "FF9500"))
                        }
                    }

                    Toggle(isOn: $notifyFaultUpdates) {
                        Label {
                            Text("Fault Status Updates")
                        } icon: {
                            iconCell("wrench.and.screwdriver.fill", color: Color.navyPrimary)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Document Expiry Warnings alert you when your assigned vehicle has an upcoming document renewal. Fault Status Updates notify you when your manager acknowledges or resolves a fault you reported.")
                }

                // MARK: About
                Section {
                    infoRow(icon: "app.badge.fill",    iconColor: Color.navyPrimary, label: "App",     value: "FleetIQ")
                    infoRow(icon: "number.circle.fill", iconColor: .secondary,        label: "Version",
                            value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Label {
                            Text("Privacy Policy")
                        } icon: {
                            iconCell("hand.raised.fill", color: Color(hex: "5856D6"))
                        }
                    }
                } header: {
                    Text("About")
                }

                // MARK: Sign Out
                Section {
                    Button(role: .destructive) {
                        authViewModel.signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .fontWeight(.semibold)
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

    private func iconCell(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: 30, height: 30)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
        }
    }

    private func infoRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            iconCell(icon, color: iconColor)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#Preview {
    DriverSettingsView()
        .environmentObject(AuthViewModel())
}
