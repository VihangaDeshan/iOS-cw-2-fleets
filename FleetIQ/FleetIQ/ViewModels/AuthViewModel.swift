//
//  AuthViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore

private func ensureFirebaseConfiguredForAuthViewModel() {
    if FirebaseApp.app() != nil {
        return
    }

    if Thread.isMainThread {
        FirebaseApp.configure()
        return
    }

    DispatchQueue.main.sync {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
}

// MARK: - Auth View Model
@MainActor
final class AuthViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false
    @Published var userRole: String = ""
    @Published var currentUID: String = ""
    @Published var fleetId: String = ""
    @Published var errorMessage: String = ""

    // MARK: - Private Properties
    private let authService: AuthService
    private let firestoreProvider: () -> Firestore
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Initializer
    /// Creates the AuthViewModel and starts listening to Firebase authentication state changes.
    init(
        authService: AuthService? = nil,
        firestoreProvider: @escaping () -> Firestore = { Firestore.firestore() }
    ) {
        ensureFirebaseConfiguredForAuthViewModel()
        self.authService = authService ?? AuthService()
        self.firestoreProvider = firestoreProvider
        startAuthStateListener()
    }

    // MARK: - Public Methods
    /// Signs in the current user and loads role and fleet metadata.
    func signIn(email: String, password: String) async {
        errorMessage = ""

        do {
            try await authService.signIn(email: email, password: password)
            try await refreshCurrentSession()
        } catch {
            errorMessage = error.localizedDescription
            resetAuthState()
        }
    }

    /// Signs in the current user and verifies that account role matches selected role.
    func signIn(email: String, password: String, expectedRole: String) async {
        await signIn(email: email, password: password)

        guard isAuthenticated else {
            return
        }

        let normalizedRole = userRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedExpectedRole = expectedRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedRole.isEmpty else {
            errorMessage = "Could not load account role. Please try again."
            signOut()
            return
        }

        if normalizedRole != normalizedExpectedRole {
            errorMessage = "Selected role does not match this account."
            signOut()
        }
    }

    /// Creates a new user account and stores role metadata in Firestore.
    func register(name: String, email: String, password: String, confirmPassword: String, role: String, fleetId: String) async {
        errorMessage = ""

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Name is required."
            return
        }

        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Email is required."
            return
        }

        guard !fleetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Fleet ID is required."
            return
        }

        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        do {
            try await authService.register(name: name, email: email, password: password, role: role, fleetId: fleetId)
            try await refreshCurrentSession()
        } catch {
            errorMessage = error.localizedDescription
            resetAuthState()
        }
    }

    /// Sends a Firebase password reset email to the provided address.
    func sendPasswordReset(email: String) async {
        errorMessage = ""

        do {
            try await authService.sendPasswordReset(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Signs out the current user and resets all auth-related view model state.
    func signOut() {
        do {
            try authService.signOut()
            resetAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private Methods
    /// Starts Firebase Auth state observation for login and logout updates.
    private func startAuthStateListener() {
        ensureFirebaseConfiguredForAuthViewModel()
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else {
                return
            }

            Task { @MainActor in
                if let user {
                    self.currentUID = user.uid
                    self.isAuthenticated = true
                    await self.loadUserMetadata(uid: user.uid)
                } else {
                    self.resetAuthState()
                }
            }
        }
    }

    /// Refreshes local auth state from the currently signed-in Firebase user.
    private func refreshCurrentSession() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "AuthViewModel",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "No active session found."]
            )
        }

        currentUID = user.uid
        isAuthenticated = true
        await loadUserMetadata(uid: user.uid)
    }

    /// Loads role and fleet metadata for a user from Firestore.
    private func loadUserMetadata(uid: String) async {
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            do {
                let resolvedRole = try await authService.fetchUserRole(uid: uid)
                let resolvedFleetId = try await fetchFleetId(uid: uid)
                let normalizedRole = resolvedRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let normalizedFleetId = resolvedFleetId.trimmingCharacters(in: .whitespacesAndNewlines)

                if normalizedRole == "manager" && normalizedFleetId.isEmpty {
                    throw NSError(
                        domain: "AuthViewModel",
                        code: -11,
                        userInfo: [NSLocalizedDescriptionKey: "Manager account is missing fleet setup. Please contact support or register again."]
                    )
                }

                fleetId = normalizedFleetId
                userRole = normalizedRole
                errorMessage = ""
                return
            } catch {
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    continue
                }

                errorMessage = error.localizedDescription

                // Prevent UI navigation into role-specific flows with incomplete profile metadata.
                do {
                    try authService.signOut()
                } catch {
                    // Keep original metadata error if local sign out also fails.
                }

                resetAuthState()
            }
        }
    }

    /// Fetches the fleetId field from users/{uid} in Firestore.
    private func fetchFleetId(uid: String) async throws -> String {
        let document = try await firestoreProvider().collection("users").document(uid).getDocument()
        let value = (document.data()?["fleetId"] as? String)
            ?? (document.data()?["fleetID"] as? String)
            ?? ""
        return value
    }

    /// Clears all local authentication state to the signed-out defaults.
    private func resetAuthState() {
        isAuthenticated = false
        userRole = ""
        currentUID = ""
        fleetId = ""
    }
}
