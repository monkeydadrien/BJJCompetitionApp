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
            HStack(alignment: .top, spacing: Spacing.xl) {
                ForEach(Array(rounds.enumerated()), id: \.offset) { idx, matches in
                    VStack(spacing: Spacing.lg) {
                        AppSectionLabel(roundLabel(idx + 1, total: rounds.count))
                            .padding(.bottom, Spacing.xs)

                        ForEach(matches) { match in
                            MatchCardView(match: match)
                        }
                    }
                    .frame(width: 210)
                }
            }
            .padding(Spacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(bracket.label)
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationBar()
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

            // Header — fight number + mat + time
            if match.fight != nil || match.mat != nil || match.when != nil {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if let fight = match.fight {
                            Text("Fight \(fight)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.textSecondary)
                        }
                        Spacer()
                        if let mat = match.mat {
                            Text(mat)
                                .font(.caption2)
                                .foregroundStyle(.textTertiary)
                        }
                    }
                    if let when = match.when {
                        Text(when)
                            .font(.caption2)
                            .foregroundStyle(.textTertiary)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardElevated)

                AppHairline()
            }

            // Competitors
            ForEach(Array(match.competitors.enumerated()), id: \.offset) { idx, comp in
                CompetitorRow(competitor: comp)
                if idx < match.competitors.count - 1 {
                    AppHairline()
                }
            }

            // Pad to 2 slots if only 1 competitor
            if match.competitors.count < 2 {
                AppHairline()
                CompetitorRow(
                    competitor: Competitor(
                        athleteId: nil,
                        name: nil,
                        club: nil,
                        seed: nil,
                        placeholder: "TBD"
                    )
                )
            }
        }
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Competitor row

struct CompetitorRow: View {

    let competitor: Competitor

    private var isNamed: Bool { competitor.name != nil }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let seed = competitor.seed {
                Text("\(seed)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textQuaternary)
                    .frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(competitor.displayName)
                    .font(.caption)
                    .fontWeight(isNamed ? .semibold : .regular)
                    .foregroundStyle(isNamed ? .textPrimary : .textTertiary)
                if let club = competitor.club, !club.isEmpty {
                    Text(club)
                        .font(.caption2)
                        .foregroundStyle(.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs + 2)
    }
}
