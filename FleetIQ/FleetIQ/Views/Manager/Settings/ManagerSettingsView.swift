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

    // Security
    @AppStorage("faceIDEnabled")      private var faceIDEnabled      = false
    @AppStorage("isUnlocked")         private var isUnlocked         = false
    @AppStorage("lockOnBackground")   private var lockOnBackground   = true

    // Notifications
    @AppStorage("notifyServiceDue")    private var notifyServiceDue    = true
    @AppStorage("notifyExpiryWarnings") private var notifyExpiryWarnings = true
    @AppStorage("notifyCriticalFaults") private var notifyCriticalFaults = true

    // MARK: - Initials
    private var managerInitials: String {
        let name = authViewModel.currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    NavigationLink(destination: UserProfileView().environmentObject(authViewModel)) {
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
                                Text(managerInitials)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(authViewModel.currentUserName.isEmpty ? "Manager" : authViewModel.currentUserName)
                                    .font(.headline.weight(.semibold))
                                Text("Manager · \(authViewModel.fleetId.isEmpty ? "No fleet" : authViewModel.fleetId)")
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
                    infoRow(icon: "building.2.fill",  iconColor: Color.navyPrimary,           label: "Fleet ID",  value: authViewModel.fleetId.isEmpty ? "—" : authViewModel.fleetId)
                    infoRow(icon: "person.circle.fill", iconColor: Color(hex: "5856D6"),       label: "User ID",   value: authViewModel.currentUID.isEmpty ? "—" : String(authViewModel.currentUID.prefix(14)) + "…")
                } header: {
                    Text("Account")
                }

                // MARK: Security
                Section {
                    // Face ID
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

                    // Lock on Background — only relevant when Face ID is on
                    Toggle(isOn: $lockOnBackground) {
                        Label {
                            Text("Lock on Background")
                        } icon: {
                            iconCell("lock.fill", color: Color(hex: "FF9500"))
                        }
                    }
                    .disabled(!faceIDEnabled)

                    // Accessibility
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
                    Toggle(isOn: $notifyServiceDue) {
                        Label {
                            Text("Service Due")
                        } icon: {
                            iconCell("wrench.and.screwdriver.fill", color: Color.navyPrimary)
                        }
                    }

                    Toggle(isOn: $notifyExpiryWarnings) {
                        Label {
                            Text("Expiry Warnings")
                        } icon: {
                            iconCell("doc.badge.clock.fill", color: Color(hex: "FF9500"))
                        }
                    }

                    Toggle(isOn: $notifyCriticalFaults) {
                        Label {
                            Text("Critical Faults")
                        } icon: {
                            iconCell("exclamationmark.triangle.fill", color: Color.statusOverdue)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Controls which push notifications FleetIQ sends. Disabling a type cancels both immediate and scheduled alerts for that category.")
                }

                // MARK: About
                Section {
                    infoRow(icon: "app.badge.fill", iconColor: Color.navyPrimary, label: "App", value: "FleetIQ")
                    infoRow(icon: "number.circle.fill", iconColor: .secondary, label: "Version",
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
