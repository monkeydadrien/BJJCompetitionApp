import SwiftUI

struct BracketTreeView: View {

    let bracket: BracketPayload

    private var rounds: [[BracketMatch]] {
        let maxRound = bracket.matches.map(\.round).max() ?? 1
        return (1...maxRound).map { r in
            bracket.matches.filter { $0.round == r }
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(rounds.enumerated()), id: \.offset) { idx, matches in
                    VStack(spacing: 16) {
                        Text(roundLabel(idx + 1, total: rounds.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        ForEach(matches) { match in
                            MatchCardView(match: match)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(bracket.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roundLabel(_ round: Int, total: Int) -> String {
        if total <= 1 { return "Final" }
        if round == total { return "Final" }
        if round == total - 1 { return "Semis" }
        if round == total - 2 { return "Quarters" }
        return "Round \(round)"
    }
}

// MARK: - Match card

struct MatchCardView: View {

    let match: BracketMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if match.fight != nil || match.mat != nil {
                HStack {
                    if let fight = match.fight {
                        Text("Fight \(fight)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    if let mat = match.mat {
                        Text(mat)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))

                if let when = match.when {
                    Text(when)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray5))
                }
            }

            Divider()

            // Competitors
            ForEach(Array(match.competitors.enumerated()), id: \.offset) { idx, comp in
                CompetitorRow(competitor: comp)
                if idx < match.competitors.count - 1 {
                    Divider()
                }
            }

            // Pad to 2 slots if only 1 competitor
            if match.competitors.count < 2 {
                Divider()
                CompetitorRow(competitor: Competitor(athleteId: nil, name: nil, club: nil, seed: nil, placeholder: "TBD"))
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 200)
    }
}

struct CompetitorRow: View {

    let competitor: Competitor

    var body: some View {
        HStack(spacing: 6) {
            if let seed = competitor.seed {
                Text("\(seed)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(competitor.displayName)
                    .font(.caption)
                    .fontWeight(competitor.name != nil ? .medium : .regular)
                    .foregroundStyle(competitor.name != nil ? .primary : .secondary)
                if let club = competitor.club, !club.isEmpty {
                    Text(club)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
