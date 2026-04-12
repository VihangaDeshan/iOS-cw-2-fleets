//
//  Color+Hex.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Color Theme Extension
extension Color {
    static let navyPrimary = Color(hex: "1A3C6E")
    static let navySecondary = Color(hex: "2E5BA8")
    static let driverGreen = Color(hex: "1A6E44")
    static let statusActive = Color(hex: "34C759")
    static let statusDueSoon = Color(hex: "FF9500")
    static let statusOverdue = Color(hex: "FF3B30")
    static let chipGreenBg = Color(hex: "E4F5EA")
    static let chipGreenText = Color(hex: "1A6E44")
    static let chipOrangeBg = Color(hex: "FFF3E0")
    static let chipOrangeText = Color(hex: "B06000")
    static let chipRedBg = Color(hex: "FFEAEA")
    static let chipRedText = Color(hex: "C00010")
    static let systemGroupedBg = Color(hex: "F2F2F7")

    /// Creates a color from a 6-character hex string.
    /// - Parameter hex: Hex string like "1A3C6E".
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
