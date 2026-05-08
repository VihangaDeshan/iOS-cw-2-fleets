//
//  DriverTabView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Driver Tab View
struct DriverTabView: View {
    @State private var selectedTab: Int = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DriverHomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            NavigationStack {
                DriverFuelView()
            }
            .tabItem {
                Label("Fuel", systemImage: "fuelpump.fill")
            }
            .tag(1)

            NavigationStack {
                MyFaultHistoryView()
            }
            .tabItem {
                Label("Faults", systemImage: "exclamationmark.triangle.fill")
            }
            .tag(2)

            NavigationStack {
                DriverRecordsView()
            }
            .tabItem {
                Label("Records", systemImage: "doc.text.fill")
            }
            .tag(3)

            DriverSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(.navyPrimary)
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
