//
//  FleetIQApp.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-11.
//

import SwiftUI
import CoreData
import UIKit
#if canImport(Firebase)
import Firebase
#elseif canImport(FirebaseCore)
import FirebaseCore
import FirebaseFirestore
#endif
import UserNotifications

// MARK: - Firebase Bootstrap
/// Configures Firebase and Firestore settings when SDKs are available.
/// Must be called as early as possible in app initialization.
private func configureFirebaseIfAvailable() {
#if canImport(Firebase)
    if FirebaseApp.app() == nil {
        FirebaseApp.configure()
    }
#elseif canImport(FirebaseCore)
    if FirebaseApp.app() == nil {
        FirebaseApp.configure()
    }
#endif
}

// MARK: - App Delegate
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Handles launch-time setup for Firebase-backed services.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureFirebaseIfAvailable()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .badge, .sound])
        } else {
            completionHandler([.alert, .badge, .sound])
        }
    }
}

@main
struct FleetIQApp: App {
    // MARK: - Properties
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let persistenceController = PersistenceController.shared
    @StateObject private var authViewModel: AuthViewModel

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("isUnlocked") private var isUnlocked: Bool = false
    @AppStorage("faceIDEnabled") private var faceIDEnabled: Bool = false
    @AppStorage("lastSelectedRole") private var lastSelectedRole: String = "manager"

    // MARK: - Initializer
    /// Creates app-level state objects.
    init() {
        configureFirebaseIfAvailable()

        // Apply Firestore settings once, immediately after Firebase configure and
        // before AuthViewModel (which calls Firestore.firestore() on auth restore).
        let fsSettings = FirestoreSettings()
        fsSettings.cacheSettings = PersistentCacheSettings()
        fsSettings.isSSLEnabled = true
        Firestore.firestore().settings = fsSettings

        _authViewModel = StateObject(wrappedValue: AuthViewModel())

        if faceIDEnabled {
            isUnlocked = false
        }
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasSeenOnboarding {
                    OnboardingView()
                } else if faceIDEnabled && !isUnlocked {
                    LockScreenView()
                } else if !authViewModel.isAuthenticated {
                    if faceIDEnabled {
                        NavigationStack {
                            LoginView(
                                role: rememberedRoleForQuickLogin,
                                showsBackButton: false,
                                showChangeRoleAction: true
                            )
                        }
                    } else {
                        RoleSelectionView()
                    }
                } else if authViewModel.userRole.isEmpty {
                    AuthLoadingView()
                } else if authViewModel.userRole == "manager" {
                    ManagerTabView()
                } else {
                    DriverTabView()
                }
            }
            .environmentObject(authViewModel)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .task {
                authViewModel.startAuthStateListenerIfNeeded()
                await NotificationService.shared.requestPermission()
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
            }
            .onChange(of: isUnlocked) { _, unlocked in
                guard unlocked,
                      authViewModel.isAuthenticated,
                      !authViewModel.userRole.isEmpty else { return }
                NotificationService.shared.resetSessionState()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    NotificationCenter.default.post(name: .appSessionDidActivate, object: nil)
                }
            }
            .onChange(of: authViewModel.userRole) { _, role in
                let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalizedRole.isEmpty else {
                    return
                }

                lastSelectedRole = normalizedRole
            }
        }
    }

    // MARK: - Private Methods
    /// Returns a valid role key for quick-login after Face Lock unlock.
    private var rememberedRoleForQuickLogin: String {
        let normalizedRole = lastSelectedRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedRole == "driver" ? "driver" : "manager"
    }

    /// Applies lock behavior for app lifecycle transitions.
    /// - Parameter phase: Current SwiftUI scene phase.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background && faceIDEnabled {
            isUnlocked = false
            return
        }

        if phase == .active {
            // When Face ID is required, defer triggering until isUnlocked fires.
            let isLocked = faceIDEnabled && !isUnlocked
            guard !isLocked,
                  authViewModel.isAuthenticated,
                  !authViewModel.userRole.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(name: .appSessionDidActivate, object: nil)
            }
        }
    }
}

// MARK: - Session Activation Notification
extension Notification.Name {
    static let appSessionDidActivate = Notification.Name("FleetIQ.appSessionDidActivate")
}

// MARK: - Temporary Dashboard Placeholders
private struct AuthLoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.navyPrimary, Color(red: 0.14, green: 0.3, blue: 0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)

                Text("Loading your account...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct ManagerDashboardPlaceholderView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.navyPrimary, Color(red: 0.14, green: 0.3, blue: 0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Manager Dashboard")
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(.white)

                Text("Role: \(authViewModel.userRole.capitalized)")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.72))

                Text("UID: \(authViewModel.currentUID)")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Button(action: authViewModel.signOut) {
                    Text("Sign Out")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 10)
            }
            .padding(22)
        }
    }
}

private struct DriverDashboardPlaceholderView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.navyPrimary, Color(red: 0.14, green: 0.3, blue: 0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Driver Dashboard")
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(.white)

                Text("Role: \(authViewModel.userRole.capitalized)")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.72))

                Text("UID: \(authViewModel.currentUID)")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Button(action: authViewModel.signOut) {
                    Text("Sign Out")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 10)
            }
            .padding(22)
        }
    }
}
