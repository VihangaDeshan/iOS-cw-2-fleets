//
//  PrivacyPolicyView.swift
//  FleetIQ
//

import SwiftUI

// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Privacy Policy")
                        .font(.largeTitle.weight(.bold))
                    Text("Effective: April 2026")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                policySection(
                    title: "Overview",
                    body: "FleetIQ is a fleet management application for business use. This policy explains what data we collect, why we collect it, and how it is protected. By using FleetIQ you agree to these terms."
                )

                policySection(
                    title: "Data We Collect",
                    items: [
                        ("Account information", "Name, email address, phone number, and role (Manager or Driver), collected at registration."),
                        ("Fleet data", "Vehicle registrations, service records, fuel logs, trip logs, and fault reports entered by your organisation."),
                        ("Location data", "GPS coordinates captured only during active trips with your explicit action. Location is not tracked in the background."),
                        ("Device data", "App version and device locale, used solely for support and crash diagnostics."),
                    ]
                )

                policySection(
                    title: "How We Use Your Data",
                    items: [
                        ("Fleet operations", "Display dashboards, generate reports, and send maintenance alerts."),
                        ("Notifications", "Push alerts for service due dates, document expiry, fault updates, and login confirmations."),
                        ("Security", "Face ID preference is stored on-device only. Passwords are managed entirely by Firebase Authentication and are never stored by FleetIQ."),
                    ]
                )

                policySection(
                    title: "Data Storage & Security",
                    body: "All data is stored in Google Firebase (Firestore & Authentication). Data is encrypted in transit (TLS) and at rest. Fleet data is scoped to your Fleet ID — other organisations cannot access your records. Local offline data is stored in CoreData on your device and cleared on sign-out."
                )

                policySection(
                    title: "Data Sharing",
                    body: "FleetIQ does not sell, rent, or share your personal data with third parties. Data is shared only within your organisation (between Managers and Drivers of the same fleet) as required for normal app operation."
                )

                policySection(
                    title: "Data Retention",
                    body: "Your data is retained for as long as your account is active. You may request account and data deletion by contacting your fleet administrator or emailing support."
                )

                policySection(
                    title: "Your Rights",
                    items: [
                        ("Access", "You can view your profile information at any time from the Profile page."),
                        ("Correction", "Update your name and phone number from the Edit Profile page."),
                        ("Deletion", "Contact your administrator or our support team to request full data deletion."),
                    ]
                )

                policySection(
                    title: "Contact",
                    body: "For privacy questions or data requests, contact your fleet administrator or reach us at support@fleetiq.app."
                )

                Text("This policy may be updated periodically. Continued use of FleetIQ after changes constitutes acceptance of the updated policy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Builders

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func policySection(title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().padding(.leading, 16) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0)
                        .font(.subheadline.weight(.medium))
                    Text(item.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
