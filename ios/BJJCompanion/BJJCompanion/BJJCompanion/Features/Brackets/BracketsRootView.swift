import SwiftUI

struct BracketsRootView: View {

    @Environment(BracketRepository.self) private var repo
    @State private var selectedTournament: Tournament?
    @State private var selectedGenderId = 1  // 1 = Male, 2 = Female
    @State private var selectedCategory: BracketCategory?

    var body: some View {
        NavigationStack {
            Form {
                // Tournament picker
                Section("Tournament") {
                    if repo.tournaments.isEmpty {
                        Button("Load Tournaments") {
                            Task { await repo.loadTournaments() }
                        }
                    } else {
                        Picker("Tournament", selection: $selectedTournament) {
                            Text("Select…").tag(Optional<Tournament>.none)
                            ForEach(repo.tournaments) { t in
                                Text(t.name).tag(Optional(t))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.navigationLink)
                        .onChange(of: selectedTournament) {
                            selectedCategory = nil
                            repo.bracket = nil
                            if let t = selectedTournament {
                                Task { await repo.loadCategories(tournamentId: t.id, genderId: selectedGenderId) }
                            }
                        }
                    }
                }

                // Gender picker
                if selectedTournament != nil {
                    Section("Gender") {
                        Picker("Gender", selection: $selectedGenderId) {
                            Text("Male").tag(1)
                            Text("Female").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedGenderId) {
                            selectedCategory = nil
                            repo.bracket = nil
                            if let t = selectedTournament {
                                Task { await repo.loadCategories(tournamentId: t.id, genderId: selectedGenderId) }
                            }
                        }
                    }

                    // Category picker
                    Section("Bracket") {
                        if repo.isLoading {
                            ProgressView("Loading categories…")
                        } else if repo.categories.isEmpty {
                            Text("No categories available")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Bracket", selection: $selectedCategory) {
                                Text("Select…").tag(Optional<BracketCategory>.none)
                                ForEach(repo.categories) { cat in
                                    Text(cat.label).tag(Optional(cat))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.navigationLink)
                            .onChange(of: selectedCategory) {
                                if let t = selectedTournament, let c = selectedCategory {
                                    Task { await repo.loadBracket(tournamentId: t.id, categoryId: c.id) }
                                }
                            }
                        }
                    }
                }

                // Bracket view
                if let bracket = repo.bracket {
                    Section("Bracket — \(bracket.label)") {
                        NavigationLink("View Full Bracket (\(bracket.matches.count) matches)") {
                            BracketTreeView(bracket: bracket)
                        }
                    }
                }

                if let error = repo.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Brackets")
            .task { if repo.tournaments.isEmpty { await repo.loadTournaments() } }
        }
    }
}
