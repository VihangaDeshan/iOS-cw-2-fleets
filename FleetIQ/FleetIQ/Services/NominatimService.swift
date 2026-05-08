//
//  NominatimService.swift
//  FleetIQ
//
//  
//

// MARK: - Garage search strategy
// 1. Try MKLocalSearch (Apple Maps) first — has phone numbers, works in supported countries.
// 2. If Apple Maps returns zero results (e.g. Sri Lanka has no POI coverage), fall back to
//    Nominatim via the OpenStreetMap Overpass API which has full Sri Lanka coverage.
// MapKit: map rendering + Apple Maps POI search
// CoreLocation: distance calculations (phone sensor interaction)
// URLSession + Nominatim: external API fallback
//
// Simulator testing:
// Simulator menu -> Features -> Location -> Custom Location
// Use the fault's current area, then widen the Nominatim radius if no garages appear.

import Foundation
import CoreLocation
import MapKit

struct NominatimResult: Codable, Identifiable {
    var id: UUID = UUID()
    let displayName: String
    let lat: String
    let lon: String
    var phone: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double(lat) ?? 0,
            longitude: Double(lon) ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case lat, lon
    }
}

private struct NominatimReverseGeocodeResult: Decodable {
    struct Address: Decodable {
        let city: String?
        let town: String?
        let village: String?
        let suburb: String?
        let county: String?
        let stateDistrict: String?
        let state: String?
        let region: String?
    }

    let address: Address

    enum CodingKeys: String, CodingKey {
        case address
    }

    enum AddressCodingKeys: String, CodingKey {
        case city
        case town
        case village
        case suburb
        case county
        case stateDistrict = "state_district"
        case state
        case region
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let addressContainer = try container.nestedContainer(keyedBy: AddressCodingKeys.self, forKey: .address)

        address = Address(
            city: try addressContainer.decodeIfPresent(String.self, forKey: .city),
            town: try addressContainer.decodeIfPresent(String.self, forKey: .town),
            village: try addressContainer.decodeIfPresent(String.self, forKey: .village),
            suburb: try addressContainer.decodeIfPresent(String.self, forKey: .suburb),
            county: try addressContainer.decodeIfPresent(String.self, forKey: .county),
            stateDistrict: try addressContainer.decodeIfPresent(String.self, forKey: .stateDistrict),
            state: try addressContainer.decodeIfPresent(String.self, forKey: .state),
            region: try addressContainer.decodeIfPresent(String.self, forKey: .region)
        )
    }
}

private struct OverpassResponse: Decodable {
    struct Element: Decodable {
        struct Center: Decodable {
            let lat: Double
            let lon: Double
        }

        let type: String
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]?
    }

    let elements: [Element]
}

final class NominatimService {
    static let shared = NominatimService()
    private init() {}

    /// Finds nearest vehicle repair garages near a coordinate.
    /// Tries Apple Maps (MKLocalSearch) first; falls back to Overpass/Nominatim for
    /// regions with no Apple Maps POI coverage (e.g. Sri Lanka).
    func findNearestGarages(
        latitude: Double,
        longitude: Double,
        limit: Int = 3
    ) async throws -> [NominatimResult] {
        let appleMapsResults = await searchGaragesAppleMaps(
            latitude: latitude,
            longitude: longitude,
            limit: limit
        )
        if !appleMapsResults.isEmpty {
            return appleMapsResults
        }

        let searchPlan: [Double] = [3, 8, 15, 30, 50]
        for radiusKm in searchPlan {
            let results = try await searchGarages(
                latitude: latitude,
                longitude: longitude,
                limit: limit,
                radiusKm: radiusKm
            )
            if !results.isEmpty {
                return results
            }
        }

        return []
    }

    /// Searches for garages using Apple Maps (MKLocalSearch).
    /// Returns an empty array if Apple Maps has no POI coverage for the region.
    private func searchGaragesAppleMaps(
        latitude: Double,
        longitude: Double,
        limit: Int
    ) async -> [NominatimResult] {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 10_000,
            longitudinalMeters: 10_000
        )

        var allItems: [MKMapItem] = []
        let queries = ["car repair", "auto garage", "mechanic"]

        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            request.resultTypes = .pointOfInterest

            let items = await withCheckedContinuation { (continuation: CheckedContinuation<[MKMapItem], Never>) in
                MKLocalSearch(request: request).start { response, _ in
                    continuation.resume(returning: response?.mapItems ?? [])
                }
            }
            allItems.append(contentsOf: items)
        }

        // Deduplicate items that are within 50 m of each other
        var unique: [MKMapItem] = []
        for item in allItems {
            let alreadyPresent = unique.contains {
                distanceKm(from: $0.placemark.coordinate, to: item.placemark.coordinate) < 0.05
            }
            if !alreadyPresent { unique.append(item) }
        }

        let driverCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return Array(
            unique
                .sorted {
                    distanceKm(from: driverCoordinate, to: $0.placemark.coordinate)
                        < distanceKm(from: driverCoordinate, to: $1.placemark.coordinate)
                }
                .prefix(limit)
                .map { item in
                    NominatimResult(
                        displayName: item.name ?? "Nearby Garage",
                        lat: String(item.placemark.coordinate.latitude),
                        lon: String(item.placemark.coordinate.longitude),
                        phone: item.phoneNumber
                    )
                }
        )
    }

    private func searchGarages(
        latitude: Double,
        longitude: Double,
        limit: Int,
        radiusKm: Double
    ) async throws -> [NominatimResult] {
        let overpassQuery = makeOverpassQuery(
            latitude: latitude,
            longitude: longitude,
            radiusKm: radiusKm,
            limit: limit
        )

        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = overpassQuery.data(using: .utf8)
        request.setValue(
            "FleetIQ/1.0 University Project",
            forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OverpassResponse.self, from: data)

        let driverCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let garages = decoded.elements.compactMap { element -> NominatimResult? in
            let coordinate: CLLocationCoordinate2D?
            if let lat = element.lat, let lon = element.lon {
                coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let center = element.center {
                coordinate = CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
            } else {
                coordinate = nil
            }

            guard let coordinate else {
                return nil
            }

            let name = element.tags?["name"]
                ?? element.tags?["brand"]
                ?? element.tags?["operator"]
                ?? "Nearby Garage"

            let phone = firstNonEmptyTag(
                from: element.tags,
                keys: ["phone", "contact:phone", "contact:mobile"]
            )

            return NominatimResult(
                displayName: name,
                lat: String(coordinate.latitude),
                lon: String(coordinate.longitude),
                phone: phone
            )
        }

        return Array(garages
            .sorted {
                distanceKm(from: driverCoordinate, to: $0.coordinate) < distanceKm(from: driverCoordinate, to: $1.coordinate)
            }
            .prefix(limit))
    }

    private func makeOverpassQuery(
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        limit: Int
    ) -> String {
        let radiusMeters = Int(radiusKm * 1000)

        return "[out:json][timeout:25];(node(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"car_repair\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"car_repair\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"car_repair\"];node(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"car_repair\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"car_repair\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"car_repair\"];node(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"garage\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"garage\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"garage\"];node(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"garage\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"garage\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"garage\"];node(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"tyres\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"tyres\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"tyres\"];node(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"vehicle_parts\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"vehicle_parts\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"vehicle_parts\"];node(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"motorcycle_repair\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"motorcycle_repair\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"amenity\"=\"motorcycle_repair\"];node(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"motorcycle\"];way(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"motorcycle\"];relation(around:\(radiusMeters),\(latitude),\(longitude))[\"shop\"=\"motorcycle\"];);out center tags \(limit + 5);"
    }

    /// Calculates distance in km between two coordinates.
    func distanceKm(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let fromLocation = CLLocation(
            latitude: from.latitude,
            longitude: from.longitude)
        let toLocation = CLLocation(
            latitude: to.latitude,
            longitude: to.longitude)
        let metres = fromLocation.distance(from: toLocation)
        return (metres / 1000).rounded(toPlaces: 1)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private func firstNonEmptyTag(from tags: [String: String]?, keys: [String]) -> String? {
    for key in keys {
        guard let value = tags?[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            continue
        }
        return value
    }
    return nil
}
