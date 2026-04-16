import Foundation

// MARK: - Top level

struct EventsPayload: Codable {
    let generatedAt: String
    let events: [BJJEvent]
}

// MARK: - Event

struct BJJEvent: Codable, Identifiable {
    let id: Int
    let name: String
    let slug: String
    let startDate: String   // "YYYY-MM-DD"
    let endDate: String
    let city: String
    let country: String
    let venue: String?
    let address: String?
    let registrationUrl: String
    let priceTiers: [PriceTier]
    let divisions: [Division]
    let lat: Double?        // optional — set by backend geocoding pass
    let lon: Double?

    var startDateParsed: Date? { DateFormatter.isoDate.date(from: startDate) }
    var endDateParsed: Date?   { DateFormatter.isoDate.date(from: endDate) }

    /// The next upcoming price deadline (first tier whose deadline is in the future)
    var nextDeadline: PriceTier? {
        let now = Date()
        return priceTiers
            .filter { ($0.deadlineParsed ?? .distantPast) > now }
            .sorted { ($0.deadlineParsed ?? .distantPast) < ($1.deadlineParsed ?? .distantPast) }
            .first
    }

    /// True when the event offers a Gi + No-Gi combo registration option.
    var hasCombo: Bool {
        priceTiers.contains { $0.name.contains("Combo") }
    }

    private static let kidsBelts: Set<String> = ["GREY", "GREY, YELLOW", "YELLOW", "ORANGE", "GREEN"]

    var hasAdultDivisions: Bool {
        divisions.contains { !Self.kidsBelts.contains($0.belt.uppercased()) }
    }

    var hasKidsDivisions: Bool {
        divisions.contains { Self.kidsBelts.contains($0.belt.uppercased()) }
    }
}

// MARK: - Price tier

struct PriceTier: Codable {
    let name: String
    let price: Double
    let deadline: String    // "YYYY-MM-DD"

    var deadlineParsed: Date? { DateFormatter.isoDate.date(from: deadline) }

    var priceFormatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: price)) ?? "$\(price)"
    }

    var deadlineFormatted: String {
        guard let d = deadlineParsed else { return deadline }
        return DateFormatter.display.string(from: d)
    }
}

// MARK: - Division

struct Division: Codable, Identifiable {
    var id: String { "\(belt)/\(ageDivision)/\(gender)/\(weightClass)" }
    let belt: String
    let ageDivision: String
    let gender: String
    let weightClass: String
    let athletes: [Athlete]

    var count: Int { athletes.count }

    func matches(_ myDivision: MyDivision) -> Bool {
        belt.lowercased()        == myDivision.belt.lowercased() &&
        ageDivision.lowercased() == myDivision.ageDivision.lowercased() &&
        gender.lowercased()      == myDivision.gender.lowercased() &&
        weightClass.lowercased() == myDivision.weightClass.lowercased()
    }
}

// MARK: - Athlete

struct Athlete: Codable, Identifiable {
    var id: String { "\(name)/\(team)" }
    let name: String
    let team: String
}

// MARK: - Tracked team / athlete

struct TrackedTeam: Codable, Identifiable, Hashable {
    var id: String { name.lowercased() }
    let name: String
}

struct TrackedAthlete: Codable, Identifiable, Hashable {
    var id: String {
        if let bid = bjjcsId { return "bjjcs:\(bid)" }
        return "\(name.lowercased())/\(team?.lowercased() ?? "")"
    }
    let name: String
    let team: String?    // optional — used to disambiguate athletes with same name
    let bjjcsId: Int?    // optional — bjjcompsystem athlete id when picked from registry
}

// MARK: - Registry athlete (from athletes.json)

struct RegistryAthlete: Codable, Identifiable, Hashable, Sendable {
    let id: Int                       // bjjcompsystem athleteId (or sequential for IBJJF-sourced)
    let name: String
    let team: String
    let lastSeenTournamentId: Int
    let lastSeenDate: String?         // "YYYY-MM-DD" or nil if undateable
}

struct AthletesPayload: Codable, Sendable {
    let generatedAt: String
    let oldestTournamentDate: String?
    let count: Int
    let athletes: [RegistryAthlete]
}

/// A single match entry returned when searching brackets for a tracked name.
struct AthleteScheduleEntry: Identifiable {
    let id = UUID()
    let athleteName: String
    let teamName: String
    let categoryLabel: String
    let tournamentId: Int
    let categoryId: Int
    let fight: Int?
    let mat: String?
    let when: String?
    let round: Int
    let opponent: String?
}

// MARK: - User's saved division

struct MyDivision: Codable, Identifiable, Hashable {
    var id: String { "\(gender)/\(ageDivision)/\(belt)/\(weightClass)" }
    var gender: String
    var ageDivision: String
    var belt: String
    var weightClass: String

    var displayLabel: String { "\(belt) / \(ageDivision) / \(gender) / \(weightClass)" }
}

// MARK: - Bracket models (from proxy)

struct BracketPayload: Codable {
    let tournamentId: Int
    let categoryId: Int
    let label: String
    let matches: [BracketMatch]
}

struct BracketMatch: Codable, Identifiable {
    var id: String { slot.isEmpty ? "\(fight ?? 0)" : slot }
    let fight: Int?
    let mat: String?
    let when: String?
    let round: Int
    let slot: String
    let competitors: [Competitor]
    let nextFight: Int?
}

struct Competitor: Codable {
    let athleteId: Int?
    let name: String?
    let club: String?
    let seed: Int?
    let placeholder: String?

    var displayName: String {
        name ?? placeholder ?? "TBD"
    }
}

struct Tournament: Codable, Identifiable, Hashable, Equatable {
    let id: Int
    let name: String
}

struct BracketCategory: Codable, Identifiable, Hashable, Equatable {
    let id: Int
    let tournamentId: Int
    let gender: String
    let label: String
}

// MARK: - Schedule response (from /schedule proxy endpoint)

struct ScheduleResponse: Codable {
    let tournamentId: Int
    let matches: [ScheduleMatch]
}

struct ScheduleMatch: Codable, Identifiable {
    var id: String { "\(categoryId)-\(fight ?? 0)-\(athleteName ?? "tbd")" }
    let athleteName: String?
    let teamName: String?
    let categoryLabel: String
    let categoryId: Int
    let tournamentId: Int
    let fight: Int?
    let mat: String?
    let when: String?
    let round: Int
    let opponent: String?

    enum CodingKeys: String, CodingKey {
        case athleteName, teamName, categoryLabel, categoryId, tournamentId,
             fight, mat, when, round, opponent
    }
}

// MARK: - Home city (user setting)

struct HomeCity: Codable, Equatable, Hashable {
    let label: String     // "Houston, Texas, United States"
    let lat: Double
    let lon: Double
}

extension BJJEvent {
    /// Great-circle distance from a home city, in miles. Returns nil if either
    /// the home city is unset or the event has no geocoded coordinates.
    func milesFrom(_ home: HomeCity?) -> Double? {
        guard let home, let lat, let lon else { return nil }
        let earthRadiusMiles = 3958.8
        let dLat = (lat - home.lat) * .pi / 180
        let dLon = (lon - home.lon) * .pi / 180
        let homeLatRad = home.lat * .pi / 180
        let evLatRad = lat * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
              + cos(homeLatRad) * cos(evLatRad)
              * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMiles * c
    }
}

// MARK: - Helpers

extension DateFormatter {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
