//
//  AuthService.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore

private func ensureFirebaseConfiguredForAuthService() {
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

// MARK: - Auth Service
final class AuthService {
    // MARK: - Properties
    private let authProvider: () -> Auth
    private let firestoreProvider: () -> Firestore

    private var auth: Auth {
        authProvider()
    }

    private var firestore: Firestore {
        firestoreProvider()
    }

    // MARK: - Initializer
    /// Creates an AuthService with Firebase Auth and Firestore dependencies.
    init(
        authProvider: @escaping () -> Auth = {
            ensureFirebaseConfiguredForAuthService()
            return Auth.auth()
        },
        firestoreProvider: @escaping () -> Firestore = {
            ensureFirebaseConfiguredForAuthService()
            return Firestore.firestore()
        }
    ) {
        self.authProvider = authProvider
        self.firestoreProvider = firestoreProvider
    }

    // MARK: - Public Methods
    /// Signs in with email and password via Firebase Auth.
    func signIn(email: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            auth.signIn(withEmail: email, password: password) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }

    /// Creates new account and saves role to Firestore users collection.
    func register(name: String, email: String, password: String, role: String, fleetId: String) async throws {
        let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let authResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            auth.createUser(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    let unexpected = NSError(
                        domain: "AuthService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Registration failed. Please try again."]
                    )
                    continuation.resume(throwing: unexpected)
                    return
                }

                continuation.resume(returning: result)
            }
        }

        var data: [String: Any] = [
            "name": name,
            "email": email,
            "role": normalizedRole,
            "fleetId": fleetId,
            "createdAt": Timestamp(date: Date())
        ]

        if normalizedRole == "driver" {
            data["assignedVehicleId"] = ""
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            firestore.collection("users").document(authResult.user.uid).setData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }

    /// Sends password reset email via Firebase Auth.
    func sendPasswordReset(email: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            auth.sendPasswordReset(withEmail: email) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }

    /// Signs out current user.
    func signOut() throws {
        try auth.signOut()
    }

    /// Fetches user role from Firestore users/{uid} document.
    func fetchUserRole(uid: String) async throws -> String {
        let document = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            firestore.collection("users").document(uid).getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let snapshot else {
                    let unexpected = NSError(
                        domain: "AuthService",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "User profile not found."]
                    )
                    continuation.resume(throwing: unexpected)
                    return
                }

                continuation.resume(returning: snapshot)
            }
        }

        guard let role = document.data()?["role"] as? String, !role.isEmpty else {
            throw NSError(
                domain: "AuthService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "User role is missing."]
            )
        }

        return role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
