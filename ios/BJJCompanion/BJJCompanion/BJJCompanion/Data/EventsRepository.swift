import Foundation
import Observation

@Observable
final class EventsRepository {

    private(set) var events: [BJJEvent] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    private let cacheURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("events_cache.json")
    }()

    // MARK: - Public

    func loadIfNeeded() async {
        if let cached = loadFromDisk(), !isStale(cached.generatedAt) {
            apply(cached)
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
            let (data, _) = try await URLSession.shared.data(from: Config.eventsURL)
            let payload = try JSONDecoder().decode(EventsPayload.self, from: data)
            apply(payload)
            saveToDisk(data)
        } catch {
            errorMessage = error.localizedDescription
            // Fall back to disk cache if available
            if events.isEmpty, let cached = loadFromDisk() {
                apply(cached)
            }
        }
    }

    // MARK: - Private

    private func apply(_ payload: EventsPayload) {
        events = payload.events
        lastUpdated = Date()
    }

    private func isStale(_ generatedAt: String) -> Bool {
        guard let date = ISO8601DateFormatter().date(from: generatedAt) else { return true }
        return Date().timeIntervalSince(date) > Config.staleDuration
    }

    private func saveToDisk(_ data: Data) {
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadFromDisk() -> EventsPayload? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(EventsPayload.self, from: data)
    }
}
