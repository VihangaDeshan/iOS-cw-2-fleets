//
//  FleetIQApp.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-11.
//

import SwiftUI
import CoreData
#if canImport(Firebase)
import Firebase
#elseif canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// MARK: - App Delegate
final class AppDelegate: NSObject, UIApplicationDelegate {}

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
    /// Configures Firebase services during app launch.
    init() {
        Self.configureFirebaseIfAvailable()
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
                    DriverDashboardPlaceholderView()
                }
            }
            .environmentObject(authViewModel)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
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
    /// Configures Firebase App and enables Firestore offline persistence when Firebase SDKs are available.
    private static func configureFirebaseIfAvailable() {
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
#endif

#if canImport(FirebaseFirestore)
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
#endif
    }

    /// Returns a valid role key for quick-login after Face Lock unlock.
    private var rememberedRoleForQuickLogin: String {
        let normalizedRole = lastSelectedRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedRole == "driver" ? "driver" : "manager"
    }

    /// Applies lock behavior for app lifecycle transitions.
    /// - Parameter phase: Current SwiftUI scene phase.
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard faceIDEnabled else {
            return
        }

        if phase == .background {
            isUnlocked = false
        }
    }
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
