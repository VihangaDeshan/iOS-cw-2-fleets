//
//  VehicleStatusChip.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Vehicle Status Chip
struct VehicleStatusChip: View {
    // MARK: - Stored Properties
    let status: String

    // MARK: - Computed Properties
    var chipBackground: Color {
        switch status {
        case "Overdue":
            return .chipRedBg
        case "Due Soon":
            return .chipOrangeBg
        default:
            return .chipGreenBg
        }
    }

    var chipText: Color {
        switch status {
        case "Overdue":
            return .chipRedText
        case "Due Soon":
            return .chipOrangeText
        default:
            return .chipGreenText
        }
    }

    // MARK: - Body
    var body: some View {
        Text(status)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(chipText)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(chipBackground)
            .clipShape(Capsule())
            .accessibilityLabel("Vehicle status: \(status)")
    }
}

#Preview {
    VStack(spacing: 8) {
        VehicleStatusChip(status: "Active")
        VehicleStatusChip(status: "Due Soon")
        VehicleStatusChip(status: "Overdue")
    }
    .padding()
}
