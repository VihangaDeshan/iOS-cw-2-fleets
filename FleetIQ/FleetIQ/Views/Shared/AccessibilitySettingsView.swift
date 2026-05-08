//
//  AccessibilitySettingsView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Accessibility Settings View
struct AccessibilitySettingsView: View {
    @AppStorage("accessibilityBoldText")    private var boldText    = false
    @AppStorage("accessibilityReduceMotion") private var reduceMotion = false
    @AppStorage("accessibilityTextSize")   private var textSize    = "default"

    var body: some View {
        List {
            // MARK: Vision
            Section {
                // Text Size
                HStack {
                    iconCell("textformat.size", color: Color(hex: "5856D6"))
                    Picker("Text Size", selection: $textSize) {
                        Text("Default").tag("default")
                        Text("Large").tag("large")
                        Text("Extra Large").tag("extraLarge")
                    }
                }

                // Bold Text
                Toggle(isOn: $boldText) {
                    Label {
                        Text("Bold Text")
                    } icon: {
                        iconCell("bold", color: .primary)
                    }
                }
            } header: {
                Text("Vision")
            } footer: {
                Text("Text changes apply within FleetIQ immediately. Bold Text makes all labels heavier for easier reading.")
            }

            // MARK: Motion
            Section {
                Toggle(isOn: $reduceMotion) {
                    Label {
                        Text("Reduce Motion")
                    } icon: {
                        iconCell("circle.dotted", color: Color(hex: "FF9500"))
                    }
                }
            } header: {
                Text("Motion")
            } footer: {
                Text("Reduces auto-scrolling animations on home dashboards and transitions throughout the app.")
            }

            // MARK: System
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        iconCell("gear", color: .gray)
                        Text("iOS Accessibility Settings")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("System")
            } footer: {
                Text("For VoiceOver, Display & Text Size, Switch Control and other system-level accessibility features, visit iOS Settings › Accessibility.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Icon helper
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
}

#Preview {
    NavigationStack { AccessibilitySettingsView() }
}
