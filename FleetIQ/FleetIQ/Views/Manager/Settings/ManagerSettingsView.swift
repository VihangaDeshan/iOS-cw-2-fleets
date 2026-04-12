//
//  ManagerSettingsView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI

// MARK: - Manager Settings View
struct ManagerSettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("isUnlocked") private var isUnlocked = false

    var body: some View {
        NavigationStack {
            List {
                Section("ACCOUNT") {
                    infoRow(title: "Role", value: authViewModel.userRole.capitalized)
                    infoRow(title: "Fleet ID", value: authViewModel.fleetId)
                    infoRow(title: "User ID", value: authViewModel.currentUID)
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "-" : value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
