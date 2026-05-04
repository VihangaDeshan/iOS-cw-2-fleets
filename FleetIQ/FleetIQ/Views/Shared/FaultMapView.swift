//
//  FaultMapView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-05-04.
//

import SwiftUI
import MapKit

// MARK: - Fault Map View
struct FaultMapView: View {
    let driverCoordinate: CLLocationCoordinate2D
    let garages: [NominatimResult]

    private let nominatimService = NominatimService.shared
    @State private var cameraPosition: MapCameraPosition

    init(
        driverCoordinate: CLLocationCoordinate2D,
        garages: [NominatimResult]
    ) {
        self.driverCoordinate = driverCoordinate
        self.garages = garages

        let region = MKCoordinateRegion(
            center: driverCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        _cameraPosition = State(
            initialValue: .region(region)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(position: $cameraPosition) {
                Annotation("Driver", coordinate: driverCoordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 32, height: 32)

                        Image(systemName: "person.fill")
                            .foregroundStyle(.white)
                            .font(.caption.weight(.semibold))
                    }
                    .shadow(radius: 3)
                }

                ForEach(garages) { garage in
                    Annotation(garage.displayName, coordinate: garage.coordinate) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "FF3B30"))
                                .frame(width: 28, height: 28)

                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(.white)
                                .font(.caption2)
                        }
                        .shadow(radius: 2)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text("OpenStreetMap · Nominatim API")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Material.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            }
            .accessibilityLabel("Map showing driver location and \(garages.count) nearby garages")

            if garages.isEmpty {
                Text("No nearby garages found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(garages) { garage in
                    HStack(spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(Color(hex: "FF3B30"))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(garage.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Text(String(format: "%.1f km away",
                                        nominatimService.distanceKm(
                                            from: driverCoordinate,
                                            to: garage.coordinate)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: garage.coordinate))
                            item.name = garage.displayName
                            item.openInMaps()
                        } label: {
                            Text("Directions")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.navyPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .accessibilityLabel("Get directions to \(garage.displayName)")
                        .accessibilityHint("Opens Maps app with navigation")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)

                    if garage.id != garages.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }
}
