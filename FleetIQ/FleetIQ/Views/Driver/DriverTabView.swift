//
//  DriverTabView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Driver Tab View
struct DriverTabView: View {
    @State private var selectedTab: DriverTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            currentTabView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
        }
        .background(Color.systemGroupedBg)
    }

    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .home:
            DriverHomeView()

        case .fuel:
            DriverTabPlaceholderView(
                title: "Fuel",
                subtitle: "Fuel logging features are coming next.",
                icon: "fuelpump.fill"
            )

        case .faults:
            NavigationStack {
                MyFaultHistoryView()
            }

        case .records:
            DriverTabPlaceholderView(
                title: "Records",
                subtitle: "Driver records features are coming next.",
                icon: "doc.text"
            )

        case .settings:
            DriverTabPlaceholderView(
                title: "Settings",
                subtitle: "Driver settings features are coming next.",
                icon: "gearshape"
            )
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            ForEach(DriverTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 23, weight: .semibold))
                            .opacity(0.001)
                            .frame(height: 0)

                        Image(systemName: tab.icon)
                            .font(.system(size: 21, weight: .medium))

                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color(hex: "1562D4") : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selectedTab == tab ? Color(hex: "EEF1F5") : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Driver Tabs
private enum DriverTab: CaseIterable {
    case home
    case fuel
    case faults
    case records
    case settings

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .fuel:
            return "Fuel"
        case .faults:
            return "Faults"
        case .records:
            return "Records"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house"
        case .fuel:
            return "car"
        case .faults:
            return "exclamationmark.triangle"
        case .records:
            return "doc.text"
        case .settings:
            return "gearshape"
        }
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
