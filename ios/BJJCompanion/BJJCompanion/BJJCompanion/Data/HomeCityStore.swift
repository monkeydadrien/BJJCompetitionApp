import Foundation
import Observation
import CoreLocation
import MapKit

/// Persists the user's home city + geocoded coordinates to UserDefaults.
/// Forward geocoding needs no Info.plist permission.
@Observable
final class HomeCityStore {

    /// Currently saved home city, or nil if the user hasn't set one.
    private(set) var city: HomeCity?

    init() { load() }

    /// Look up `query` (e.g. "Houston, TX"), store the cleaned-up label + lat/lon.
    /// Uses MKGeocodingRequest (iOS 26+, our deployment target).
    /// Throws if geocoding finds no match.
    @MainActor
    func setCity(_ query: String) async throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HomeCityError.emptyQuery
        }

        let resolved = try await Self.geocode(trimmed)
        let value = HomeCity(
            label: resolved.label.isEmpty ? trimmed : resolved.label,
            lat:   resolved.coord.latitude,
            lon:   resolved.coord.longitude
        )
        self.city = value
        save()
    }

    // MARK: - Geocoding

    private struct GeocodeResult {
        let label: String
        let coord: CLLocationCoordinate2D
    }

    private static func geocode(_ query: String) async throws -> GeocodeResult {
        guard let request = MKGeocodingRequest(addressString: query) else {
            throw HomeCityError.notFound(query)
        }
        let items = try await request.mapItems
        guard let item = items.first else { throw HomeCityError.notFound(query) }
        let coord = item.location.coordinate
        // `cityWithContext` produces a friendly "City, State" / "City, Country" string.
        // Fall back to the raw query if the API doesn't return one.
        let label = item.addressRepresentations?.cityWithContext ?? query
        return GeocodeResult(label: label, coord: coord)
    }

    func clear() {
        city = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Errors

    enum HomeCityError: LocalizedError {
        case emptyQuery
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .emptyQuery:        return "Please enter a city name."
            case .notFound(let q):   return "Couldn't find a location for \"\(q)\". Try \"City, State\" or include a country."
            }
        }
    }

    // MARK: - Persistence

    private let key = "homeCity.v1"

    private func save() {
        guard let city,
              let data = try? JSONEncoder().encode(city) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(HomeCity.self, from: data)
        else { return }
        self.city = value
    }
}
