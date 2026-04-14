import Foundation
import Observation

/// Fetches and caches the IBJJF ranked athletes database (athletes.json from GitHub Pages).
@Observable
final class AthletesRepository {

    private(set) var athletes: [RankedAthlete] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    private let cacheURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("athletes_cache.json")
    }()

    // MARK: - Public

    func loadIfNeeded() async {
        if let cached = loadFromDisk() {
            apply(cached)
            // Don't re-fetch if we loaded from disk — rankings update monthly
            return
        }
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
            saveToDisk(data)
        } catch {
            errorMessage = error.localizedDescription
            if athletes.isEmpty, let cached = loadFromDisk() {
                apply(cached)
            }
        }
    }

    // MARK: - Search

    /// Fast local search — substring match on name, returns up to `limit` results.
    func search(name: String, limit: Int = 50) -> [RankedAthlete] {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [RankedAthlete] = []
        for a in athletes {
            if a.name.lowercased().contains(q) {
                results.append(a)
                if results.count >= limit { break }
            }
        }
        return results
    }

    // MARK: - Private

    private func apply(_ payload: AthletesPayload) {
        athletes = payload.athletes
        lastUpdated = Date()
    }

    private func saveToDisk(_ data: Data) {
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadFromDisk() -> AthletesPayload? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(AthletesPayload.self, from: data)
    }
}
