//
//  AuthViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - Auth View Model
@MainActor
final class AuthViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false
    @Published var userRole: String = ""
    @Published var currentUID: String = ""
    @Published var currentUserName: String = ""
    @Published var fleetId: String = ""
    @Published var assignedVehicleId: String = ""
    @Published var errorMessage: String = ""

    // MARK: - Private Properties
    private let authService: AuthService
    private let firestoreProvider: () -> Firestore
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var didStartAuthStateListener: Bool = false

    // MARK: - Initializer
    /// Creates the AuthViewModel with lazy Firebase access.
    /// Auth state listening is NOT started automatically; call startAuthStateListenerIfNeeded()
    /// after FirebaseApp.configure() has completed.
    init(
        authService: AuthService? = nil,
        firestoreProvider: @escaping () -> Firestore = {
            guard FirebaseApp.app() != nil else {
                fatalError("Firebase app has not been configured. Call FirebaseApp.configure() in app initialization.")
            }
            return Firestore.firestore()
        }
    ) {
        self.authService = authService ?? AuthService()
        self.firestoreProvider = firestoreProvider
    }

    /// Starts Firebase Auth state observation after app launch has configured Firebase.
    func startAuthStateListenerIfNeeded() {
        guard !didStartAuthStateListener else {
            return
        }

        didStartAuthStateListener = true
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
                let userData = try await fetchUserDocument(uid: uid)

                let resolvedRole = (userData["role"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let resolvedFleetId = ((userData["fleetId"] as? String)
                    ?? (userData["fleetID"] as? String)
                    ?? (userData["fleetName"] as? String)
                    ?? "")
                let resolvedName = (userData["name"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedAssignedVehicleId = (userData["assignedVehicleId"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

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
                currentUserName = resolvedName
                assignedVehicleId = resolvedAssignedVehicleId
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

    /// Fetches full user profile data from users/{uid}.
    private func fetchUserDocument(uid: String) async throws -> [String: Any] {
        let document = try await firestoreProvider().collection("users").document(uid).getDocument()
        guard let data = document.data() else {
            throw NSError(
                domain: "AuthViewModel",
                code: -12,
                userInfo: [NSLocalizedDescriptionKey: "User profile not found."]
            )
        }

        return data
    }

    /// Fetches the fleetId field from users/{uid} in Firestore.
    private func fetchFleetId(uid: String) async throws -> String {
        let document = try await firestoreProvider().collection("users").document(uid).getDocument()
        let value = (document.data()?["fleetId"] as? String)
            ?? (document.data()?["fleetID"] as? String)
            ?? (document.data()?["fleetName"] as? String)
            ?? ""
        return value
    }

    /// Clears all local authentication state to the signed-out defaults.
    private func resetAuthState() {
        isAuthenticated = false
        userRole = ""
        currentUID = ""
        currentUserName = ""
        fleetId = ""
        assignedVehicleId = ""
    }
}
