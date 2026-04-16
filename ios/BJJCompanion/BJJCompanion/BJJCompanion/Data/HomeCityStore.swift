import Foundation
import Observation
import CoreLocation

/// Persists the user's home city + geocoded coordinates to UserDefaults.
/// Forward geocoding via CLGeocoder needs no Info.plist permission.
@Observable
final class HomeCityStore {

    /// Currently saved home city, or nil if the user hasn't set one.
    private(set) var city: HomeCity?

    init() { load() }

    /// Look up `query` (e.g. "Houston, TX") with CLGeocoder, store the cleaned-
    /// up label and lat/lon. Throws if geocoding finds no match.
    @MainActor
    func setCity(_ query: String) async throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HomeCityError.emptyQuery
        }

        let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
        guard let p = placemarks.first, let loc = p.location else {
            throw HomeCityError.notFound(trimmed)
        }

        let cleanedLabel: String = {
            let parts = [p.locality, p.administrativeArea, p.country].compactMap { $0 }
            let joined = parts.joined(separator: ", ")
            return joined.isEmpty ? trimmed : joined
        }()

        let value = HomeCity(
            label: cleanedLabel,
            lat:   loc.coordinate.latitude,
            lon:   loc.coordinate.longitude
        )
        self.city = value
        save()
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
