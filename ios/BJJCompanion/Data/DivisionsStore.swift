import Foundation
import Observation

/// Persists the user's saved divisions to UserDefaults.
@Observable
final class DivisionsStore {

    var myDivisions: [MyDivision] = [] {
        didSet { save() }
    }

    init() { load() }

    // MARK: - IBJJF option lists

    static let genders       = ["Male", "Female"]
    static let ageDivisions  = ["Juvenile", "Adult", "Master 1", "Master 2", "Master 3", "Master 4", "Master 5", "Master 6", "Master 7"]
    static let belts         = ["WHITE", "BLUE", "PURPLE", "BROWN", "BLACK"]
    static let weightClasses = [
        "Rooster", "Light Feather", "Feather", "Light",
        "Middle", "Medium-Heavy", "Heavy", "Super-Heavy", "Ultra-Heavy"
    ]

    // MARK: - Persistence

    private let key = "myDivisions"

    private func save() {
        if let data = try? JSONEncoder().encode(myDivisions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([MyDivision].self, from: data) else { return }
        myDivisions = saved
    }
}
