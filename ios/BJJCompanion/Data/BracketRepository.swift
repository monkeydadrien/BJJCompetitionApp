import Foundation
import Observation

@Observable
final class BracketRepository {

    private(set) var tournaments: [Tournament] = []
    private(set) var categories: [BracketCategory] = []
    private(set) var bracket: BracketPayload?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // Schedule state — keyed by tournamentId
    private(set) var schedules: [Int: [ScheduleMatch]] = [:]
    private(set) var loadingSchedules: Set<Int> = []
    private(set) var scheduleErrors: [Int: String] = [:]

    // Simple in-memory cache keyed by "tid:cid"
    private var bracketCache: [String: BracketPayload] = [:]

    func clearBracket() {
        bracket = nil
    }

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

    // MARK: - Tournament days (mat queues)

    /// Days for the currently-selected tournament, keyed by tournament id so we
    /// don't re-fetch when the user toggles back and forth between tournaments.
    private(set) var tournamentDays: [Int: [TournamentDay]] = [:]
    /// Latest fetched mat queues, keyed by "tid:did".
    private(set) var tournamentDay: [String: TournamentDayPayload] = [:]
    private(set) var loadingTournamentDay: Set<String> = []
    private(set) var tournamentDayErrors: [String: String] = [:]

    func loadTournamentDays(tournamentId: Int) async {
        var comps = URLComponents(
            url: Config.proxyBaseURL.appendingPathComponent("tournament_days"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "tournament", value: "\(tournamentId)")]
        guard let url = comps.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let days = try JSONDecoder().decode([TournamentDay].self, from: data)
            tournamentDays[tournamentId] = days
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch a single tournament day's mat queues. Always hits the network — the
    /// proxy applies its own short TTL (45s) so polling is cheap on compsystem.
    func loadTournamentDay(tournamentId: Int, dayId: Int) async {
        let key = "\(tournamentId):\(dayId)"
        guard !loadingTournamentDay.contains(key) else { return }
        loadingTournamentDay.insert(key)
        tournamentDayErrors.removeValue(forKey: key)
        defer { loadingTournamentDay.remove(key) }

        var comps = URLComponents(
            url: Config.proxyBaseURL.appendingPathComponent("tournament_day"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "tournament", value: "\(tournamentId)"),
            URLQueryItem(name: "day",        value: "\(dayId)"),
        ]
        guard let url = comps.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let payload   = try JSONDecoder().decode(TournamentDayPayload.self, from: data)
            tournamentDay[key] = payload
        } catch {
            tournamentDayErrors[key] = error.localizedDescription
        }
    }

    // MARK: - Schedule

    func loadSchedule(tournamentId: Int, names: [String]) async {
        guard !names.isEmpty, !loadingSchedules.contains(tournamentId) else { return }
        loadingSchedules.insert(tournamentId)
        scheduleErrors.removeValue(forKey: tournamentId)
        defer { loadingSchedules.remove(tournamentId) }

        var comps = URLComponents(
            url: Config.proxyBaseURL.appendingPathComponent("schedule"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "tournament", value: "\(tournamentId)"),
            URLQueryItem(name: "names",      value: names.joined(separator: ",")),
        ]
        guard let url = comps.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response  = try JSONDecoder().decode(ScheduleResponse.self, from: data)
            schedules[tournamentId] = response.matches
        } catch {
            scheduleErrors[tournamentId] = error.localizedDescription
        }
    }

    func clearSchedule(for tournamentId: Int) {
        schedules.removeValue(forKey: tournamentId)
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
