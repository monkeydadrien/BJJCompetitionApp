import Foundation
import Observation

@Observable
final class BracketRepository {

    private(set) var tournaments: [Tournament] = []
    private(set) var categories: [BracketCategory] = []
    private(set) var bracket: BracketPayload?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // Simple in-memory cache keyed by "tid:cid"
    private var bracketCache: [String: BracketPayload] = [:]

    // MARK: - Tournaments

    func loadTournaments() async {
        await fetch(url: Config.proxyBaseURL.appendingPathComponent("tournaments")) { [weak self] (result: [Tournament]) in
            self?.tournaments = result
        }
    }

    // MARK: - Categories

    func loadCategories(tournamentId: Int, genderId: Int) async {
        var comps = URLComponents(url: Config.proxyBaseURL.appendingPathComponent("tournaments/\(tournamentId)/categories"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "gender_id", value: "\(genderId)")]
        await fetch(url: comps.url!) { [weak self] (result: [BracketCategory]) in
            self?.categories = result
        }
    }

    // MARK: - Bracket

    func loadBracket(tournamentId: Int, categoryId: Int) async {
        let key = "\(tournamentId):\(categoryId)"
        if let cached = bracketCache[key] {
            bracket = cached
            return
        }
        var comps = URLComponents(url: Config.proxyBaseURL.appendingPathComponent("bracket"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "tournament", value: "\(tournamentId)"),
            URLQueryItem(name: "category",   value: "\(categoryId)"),
        ]
        await fetch(url: comps.url!) { [weak self] (result: BracketPayload) in
            self?.bracket = result
            self?.bracketCache[key] = result
        }
    }

    // MARK: - Generic fetch

    private func fetch<T: Decodable>(url: URL, apply: @escaping (T) -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            apply(decoded)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
