//
//  AppEnvironmentKeys.swift
//  FleetIQ
//
//  Custom SwiftUI environment keys that carry in-app accessibility preferences
//  down the full view hierarchy without modifying individual views.
//

import SwiftUI

// MARK: - Reduce Motion

private struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

// MARK: - Bold Text

private struct AppBoldTextKey: EnvironmentKey {
    static let defaultValue = false
}

// MARK: - Environment Values Extensions

extension EnvironmentValues {
    /// True when the user has enabled "Reduce Motion" in FleetIQ Accessibility settings.
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }

    /// True when the user has enabled "Bold Text" in FleetIQ Accessibility settings.
    var appBoldText: Bool {
        get { self[AppBoldTextKey.self] }
        set { self[AppBoldTextKey.self] = newValue }
    }
}
