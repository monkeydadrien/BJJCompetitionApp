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
    let registrationUrl: String
    let priceTiers: [PriceTier]
    let divisions: [Division]

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

struct Tournament: Codable, Identifiable {
    let id: Int
    let name: String
}

struct BracketCategory: Codable, Identifiable {
    let id: Int
    let tournamentId: Int
    let gender: String
    let label: String
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
