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

// MARK: - Auth View Model
@MainActor
final class AuthViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false
    @Published var userRole: String = ""
    @Published var currentUID: String = ""
    @Published var fleetId: String = ""
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    // MARK: - Private Properties
    private let authService: AuthService
    private let firestore: Firestore
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Initializer
    /// Creates the AuthViewModel and starts listening to Firebase authentication state changes.
    init(authService: AuthService = AuthService(), firestore: Firestore = Firestore.firestore()) {
        self.authService = authService
        self.firestore = firestore
        startAuthStateListener()
    }

    // MARK: - Public Methods
    /// Signs in the current user and loads role and fleet metadata.
    func signIn(email: String, password: String) async {
        errorMessage = ""
        isLoading = true

        do {
            try await authService.signIn(email: email, password: password)
            try await refreshCurrentSession()
        } catch {
            errorMessage = error.localizedDescription
            resetAuthState()
        }

        isLoading = false
    }

    /// Creates a new user account and stores role metadata in Firestore.
    func register(name: String, email: String, password: String, confirmPassword: String, role: String, fleetId: String) async {
        errorMessage = ""

        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isLoading = true

        do {
            try await authService.register(name: name, email: email, password: password, role: role, fleetId: fleetId)
            try await refreshCurrentSession()
        } catch {
            errorMessage = error.localizedDescription
            resetAuthState()
        }

        isLoading = false
    }

    /// Sends a Firebase password reset email to the provided address.
    func sendPasswordReset(email: String) async {
        errorMessage = ""
        isLoading = true

        do {
            try await authService.sendPasswordReset(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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

    /// Stops Firebase Auth state observation when the view model is released.
    private func stopAuthStateListener() {
        guard let authStateHandle else {
            return
        }

        Auth.auth().removeStateDidChangeListener(authStateHandle)
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
        do {
            userRole = try await authService.fetchUserRole(uid: uid)
            fleetId = try await fetchFleetId(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the fleetId field from users/{uid} in Firestore.
    private func fetchFleetId(uid: String) async throws -> String {
        let document = try await firestore.collection("users").document(uid).getDocument()
        let value = document.data()?["fleetId"] as? String ?? ""
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
