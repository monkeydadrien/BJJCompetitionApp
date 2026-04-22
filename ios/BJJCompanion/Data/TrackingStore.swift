import Foundation
import Observation
import SwiftUI

/// Persists the user's tracked teams and athletes to UserDefaults.
@Observable
final class TrackingStore {

    var trackedTeams: [TrackedTeam] = [] {
        didSet { save(trackedTeams, forKey: teamsKey) }
    }

    var trackedAthletes: [TrackedAthlete] = [] {
        didSet { save(trackedAthletes, forKey: athletesKey) }
    }

    /// Maps IBJJF event id → compsystem tournament id (user-linked)
    var eventTournamentLinks: [String: Int] = [:] {
        didSet { save(eventTournamentLinks, forKey: linksKey) }
    }

    init() { load() }

    func linkedTournamentId(for eventId: Int) -> Int? {
        eventTournamentLinks["\(eventId)"]
    }

    func linkTournament(_ tournamentId: Int, to eventId: Int) {
        eventTournamentLinks["\(eventId)"] = tournamentId
    }

    func unlinkTournament(from eventId: Int) {
        eventTournamentLinks.removeValue(forKey: "\(eventId)")
    }

    // MARK: - Convenience

    func isTrackingTeam(_ name: String) -> Bool {
        trackedTeams.contains { $0.name.lowercased() == name.lowercased() }
    }

    func isTrackingAthlete(name: String) -> Bool {
        trackedAthletes.contains { $0.name.lowercased() == name.lowercased() }
    }

    func addTeam(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTrackingTeam(trimmed) else { return }
        trackedTeams.append(TrackedTeam(name: trimmed))
    }

    func addAthlete(name: String, team: String?, bjjcsId: Int? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTrackingAthlete(name: trimmed) else { return }
        trackedAthletes.append(TrackedAthlete(name: trimmed, team: team, bjjcsId: bjjcsId))
    }

    func removeTeams(at offsets: IndexSet)    { trackedTeams.remove(atOffsets: offsets) }
    func removeAthletes(at offsets: IndexSet) { trackedAthletes.remove(atOffsets: offsets) }

    // MARK: - Matching helpers

    /// All athletes in an event's divisions that match any tracked team or athlete.
    func matchingRegistrations(in event: BJJEvent) -> [(athlete: Athlete, division: Division)] {
        var results: [(Athlete, Division)] = []
        for division in event.divisions {
            for athlete in division.athletes {
                if matchesAnyTracked(name: athlete.name, team: athlete.team) {
                    results.append((athlete, division))
                }
            }
        }
        return results
    }

    /// Only athletes whose team matches a tracked team.
    func teamMatchingRegistrations(in event: BJJEvent) -> [(athlete: Athlete, division: Division)] {
        var results: [(Athlete, Division)] = []
        for division in event.divisions {
            for athlete in division.athletes {
                let teamLower = athlete.team.lowercased()
                let hit = trackedTeams.contains {
                    teamLower.contains($0.name.lowercased()) || $0.name.lowercased().contains(teamLower)
                }
                if hit { results.append((athlete, division)) }
            }
        }
        return results
    }

    /// Only athletes whose name exactly matches a tracked individual athlete.
    func athleteMatchingRegistrations(in event: BJJEvent) -> [(athlete: Athlete, division: Division)] {
        var results: [(Athlete, Division)] = []
        for division in event.divisions {
            for athlete in division.athletes {
                let hit = trackedAthletes.contains {
                    Self.nameMatch(tracked: $0.name, against: athlete.name)
                }
                if hit { results.append((athlete, division)) }
            }
        }
        return results
    }

    func matchesAnyTracked(name: String, team: String) -> Bool {
        let teamLower = team.lowercased()

        let teamMatch = trackedTeams.contains {
            teamLower.contains($0.name.lowercased()) || $0.name.lowercased().contains(teamLower)
        }
        let athleteMatch = trackedAthletes.contains {
            Self.nameMatch(tracked: $0.name, against: name)
        }
        return teamMatch || athleteMatch
    }

    /// Token-subset match after normalizing case, diacritics, and whitespace.
    /// Every token in the tracked name must appear in the registered name —
    /// so "Pedro Ottonello" matches "Pedro Henrique Ottonello dos Santos"
    /// (IBJJF uses full legal names, users rarely type them in full).
    /// A 2-token minimum on the tracked side prevents single-name false
    /// positives ("Pedro" matching every Pedro in the bracket).
    static func nameMatch(tracked: String, against: String) -> Bool {
        let trackedTokens = Set(normalizeAthleteName(tracked).split(separator: " ").map(String.init))
        guard trackedTokens.count >= 2 else {
            // Single-token tracked name → require exact normalized match.
            let a = normalizeAthleteName(tracked)
            guard !a.isEmpty else { return false }
            return a == normalizeAthleteName(against)
        }
        let againstTokens = Set(normalizeAthleteName(against).split(separator: " ").map(String.init))
        return trackedTokens.isSubset(of: againstTokens)
    }

    // MARK: - Persistence

    private let teamsKey    = "trackedTeams"
    private let athletesKey = "trackedAthletes"
    private let linksKey    = "eventTournamentLinks"

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: teamsKey),
           let saved = try? JSONDecoder().decode([TrackedTeam].self, from: data) {
            trackedTeams = saved
        }
        if let data = UserDefaults.standard.data(forKey: athletesKey),
           let saved = try? JSONDecoder().decode([TrackedAthlete].self, from: data) {
            trackedAthletes = saved
        }
        if let data = UserDefaults.standard.data(forKey: linksKey),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            eventTournamentLinks = saved
        }
    }
}

// MARK: - Shared normalization

/// Case / diacritic / punctuation-insensitive normalization.
/// Single source of truth used by `TrackingStore.nameMatch` AND
/// `AthletesRepository.search` so match and search can never drift.
func normalizeAthleteName(_ s: String) -> String {
    s.lowercased()
        .folding(options: .diacriticInsensitive, locale: .current)  // "José" → "jose"
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .joined(separator: " ")
}
