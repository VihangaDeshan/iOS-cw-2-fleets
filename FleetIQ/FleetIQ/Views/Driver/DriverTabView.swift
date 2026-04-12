//
//  DriverTabView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI

// MARK: - Driver Tab View
struct DriverTabView: View {
    var body: some View {
        TabView {
            DriverHomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            DriverTabPlaceholderView(
                title: "Report",
                subtitle: "Fault reporting features are coming next.",
                icon: "exclamationmark.triangle.fill"
            )
            .tabItem {
                Label("Report", systemImage: "exclamationmark.triangle.fill")
            }

            DriverTabPlaceholderView(
                title: "Trip",
                subtitle: "Trip logging features are coming next.",
                icon: "map.fill"
            )
            .tabItem {
                Label("Trip", systemImage: "map.fill")
            }

            DriverTabPlaceholderView(
                title: "Fuel",
                subtitle: "Fuel logging features are coming next.",
                icon: "fuelpump.fill"
            )
            .tabItem {
                Label("Fuel", systemImage: "fuelpump.fill")
            }

            DriverTabPlaceholderView(
                title: "Profile",
                subtitle: "Driver profile features are coming next.",
                icon: "person.crop.circle.fill"
            )
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
        }
        .tint(.driverGreen)
    }
}

// MARK: - Placeholder Tab Content
private struct DriverTabPlaceholderView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: icon,
                description: Text(subtitle)
            )
            .navigationTitle(title)
        }
    }
}

#Preview {
    DriverTabView()
}
