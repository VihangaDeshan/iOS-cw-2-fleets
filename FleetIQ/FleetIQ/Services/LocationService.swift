//
//  LocationService.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import Foundation
import CoreLocation

// MARK: - Location Service Error
enum LocationServiceError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location services are disabled on this device."
        case .permissionDenied:
            return "Location permission was denied. Enable While Using the App in Settings."
        case .locationUnavailable:
            return "Could not determine your current location."
        }
    }
}

// MARK: - Location Service
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var isRequestInProgress = false
    private var timeoutWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Requests one-time GPS location fix.
    /// Authorization is requested first when status is .notDetermined.
    func requestOneTimeLocation() async throws -> CLLocationCoordinate2D {
        let servicesEnabled = await Self.locationServicesEnabledAsync()
        guard servicesEnabled else {
            throw LocationServiceError.servicesDisabled
        }

        return try await requestOneTimeLocationOnMainActor()
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRequestInProgress else {
            return
        }

        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            complete(with: .failure(LocationServiceError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            complete(with: .failure(LocationServiceError.locationUnavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.first?.coordinate else {
            complete(with: .failure(LocationServiceError.locationUnavailable))
            return
        }

        complete(with: .success(coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        complete(with: .failure(error))
    }

    // MARK: - Private
    private func complete(with result: Result<CLLocationCoordinate2D, Error>) {
        if Thread.isMainThread {
            completeOnMain(with: result)
        } else {
            DispatchQueue.main.async {
                self.completeOnMain(with: result)
            }
        }
    }

    private func completeOnMain(with result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else {
            return
        }

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        self.continuation = nil
        self.isRequestInProgress = false

        switch result {
        case .success(let coordinate):
            continuation.resume(returning: coordinate)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    @MainActor
    private func requestOneTimeLocationOnMainActor() async throws -> CLLocationCoordinate2D {
        if isRequestInProgress {
            throw LocationServiceError.locationUnavailable
        }

        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            throw LocationServiceError.permissionDenied
        }

        if let cachedLocation = manager.location?.coordinate {
            return cachedLocation
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocationCoordinate2D, Error>) in
            self.continuation = continuation
            self.isRequestInProgress = true

            let timeout = DispatchWorkItem { [weak self] in
                guard let self else {
                    return
                }

                self.completeOnMain(with: .failure(LocationServiceError.locationUnavailable))
            }
            self.timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)

            if status == .notDetermined {
                self.manager.requestWhenInUseAuthorization()
            } else {
                self.manager.requestLocation()
            }
        }
    }

    private static func locationServicesEnabledAsync() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: CLLocationManager.locationServicesEnabled())
            }
        }
    }
}
