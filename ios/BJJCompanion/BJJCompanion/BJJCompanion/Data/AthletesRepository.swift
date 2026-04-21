import Foundation
import Observation

/// Fetches and caches the bjjcompsystem-derived athlete registry (`athletes.json`).
/// Powers autocomplete in the Add Athlete sheet.
///
/// The JSON is a few MB — we cache to the Documents directory (not UserDefaults).
/// Decode runs on the same actor as the caller; under default-MainActor isolation,
/// `AthletesPayload`'s synthesized `Decodable` conformance is MainActor-bound, so
/// hopping to a detached task is illegal in Swift 6. The file is small enough that
/// decoding inline during launch is not perceptible.
@Observable
final class AthletesRepository {

    private(set) var athletes: [RegistryAthlete] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    /// Pre-computed (normalizedName, athlete) pairs for linear-scan search.
    /// Rebuilt whenever `athletes` is replaced.
    private var searchIndex: [(normalized: String, athlete: RegistryAthlete)] = []

    private let cacheURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("athletes_cache.json")
    }()

    // MARK: - Public

    func loadIfNeeded() async {
        if await applyCachedIfFresh() { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: Config.athletesURL)
            let payload = try JSONDecoder().decode(AthletesPayload.self, from: data)
            apply(payload)
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
            // Fall back to cached data if we have none loaded yet
            if athletes.isEmpty {
                _ = await applyCachedIfFresh(ignoreStale: true)
            }
        }
    }

    /// Top-N matches for a search query. Prefix match ranks above substring.
    func search(query: String, limit: Int = 10) -> [RegistryAthlete] {
        let q = normalizeAthleteName(query)
        guard !q.isEmpty else { return [] }

        var prefixHits: [RegistryAthlete] = []
        var substringHits: [RegistryAthlete] = []

        for entry in searchIndex {
            if entry.normalized.hasPrefix(q) {
                prefixHits.append(entry.athlete)
                if prefixHits.count + substringHits.count >= limit * 3 { break }
            } else if entry.normalized.contains(q) {
                substringHits.append(entry.athlete)
            }
        }

        // The underlying array is already sorted by lastSeenDate desc, so order is preserved.
        return Array((prefixHits + substringHits).prefix(limit))
    }

    // MARK: - Private

    @discardableResult
    private func applyCachedIfFresh(ignoreStale: Bool = false) async -> Bool {
        guard let data = try? Data(contentsOf: cacheURL) else { return false }
        guard let payload = try? JSONDecoder().decode(AthletesPayload.self, from: data) else { return false }
        if !ignoreStale, isStale(payload.generatedAt) { return false }
        apply(payload)
        return true
    }

    private func apply(_ payload: AthletesPayload) {
        athletes = payload.athletes
        searchIndex = payload.athletes.map { (normalizeAthleteName($0.name), $0) }
        lastUpdated = Date()
    }

    private func isStale(_ generatedAt: String) -> Bool {
        guard let date = ISO8601DateFormatter().date(from: generatedAt) else { return true }
        return Date().timeIntervalSince(date) > Config.staleDuration
    }
}
