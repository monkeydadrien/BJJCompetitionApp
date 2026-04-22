import SwiftUI

/// Live mat-queue view for tournament day. Replaces the legacy Brackets tab as
/// the primary view; the bracket-tree picker is still reachable via a toolbar
/// menu for users who want to plan ahead.
struct MatchesRootView: View {

    @Environment(BracketRepository.self) private var repo
    @Environment(TrackingStore.self)     private var tracking

    @State private var selectedTournament: Tournament?
    @State private var selectedDayId: Int?
    @State private var selectedMatName: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
                .scrollContentBackground(.hidden)
                .background(Color.appBackground.ignoresSafeArea())
                .navigationTitle("Matches")
                .navigationBarTitleDisplayMode(.inline)
                .appNavigationBar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            BracketsRootView()
                        } label: {
                            Label("Brackets", systemImage: "trophy")
                        }
                    }
                }
                .task { if repo.tournaments.isEmpty { await repo.loadTournaments() } }
                .onDisappear { pollTask?.cancel(); pollTask = nil }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        Form {
            tournamentSection

            if let tournament = selectedTournament {
                if let days = repo.tournamentDays[tournament.id], !days.isEmpty {
                    daySection(days: days, tournament: tournament)

                    if let dayId = selectedDayId, let payload = currentDayPayload(tournament: tournament, dayId: dayId) {
                        yourFightsSection(payload: payload)
                        matSection(payload: payload)
                        matchesSection(payload: payload)
                    } else if repo.loadingTournamentDay.contains("\(tournament.id):\(selectedDayId ?? 0)") {
                        Section { ProgressView("Loading mats…") }
                    } else if let dayId = selectedDayId,
                              let err = repo.tournamentDayErrors["\(tournament.id):\(dayId)"] {
                        Section {
                            Text(err).foregroundStyle(.red).font(.caption)
                        }
                    }
                } else {
                    Section {
                        if repo.isLoading {
                            ProgressView("Loading days…")
                        } else {
                            Text("No tournament days published yet.")
                                .foregroundStyle(.textSecondary)
                                .font(.callout)
                        }
                    }
                }
            } else {
                Section {
                    Text("Pick a tournament to see today's mat schedule.")
                        .foregroundStyle(.textSecondary)
                        .font(.callout)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var tournamentSection: some View {
        Section("Tournament") {
            if repo.tournaments.isEmpty {
                if let err = repo.errorMessage {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Couldn't load tournaments")
                            .font(.callout).foregroundStyle(.textPrimary)
                        Text(err).font(.caption).foregroundStyle(.red)
                        Button("Retry") {
                            Task { await repo.loadTournaments() }
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.accent)
                    }
                } else {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().tint(.accent)
                        Text("Loading tournaments…")
                            .font(.callout).foregroundStyle(.textSecondary)
                    }
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
                .onChange(of: selectedTournament) { _, new in
                    selectedDayId = nil
                    selectedMatName = nil
                    pollTask?.cancel(); pollTask = nil
                    guard let t = new else { return }
                    Task {
                        await repo.loadTournamentDays(tournamentId: t.id)
                        // Auto-select the first day so the user lands on data
                        if let first = repo.tournamentDays[t.id]?.first {
                            selectedDayId = first.dayId
                            startPolling(tournamentId: t.id, dayId: first.dayId)
                        }
                    }
                }
            }
        }
    }

    private func daySection(days: [TournamentDay], tournament: Tournament) -> some View {
        Section("Day") {
            Picker("Day", selection: Binding(
                get: { selectedDayId ?? days.first?.dayId ?? 0 },
                set: { newValue in
                    selectedDayId = newValue
                    selectedMatName = nil
                    startPolling(tournamentId: tournament.id, dayId: newValue)
                }
            )) {
                ForEach(days) { d in
                    Text(d.shortLabel).tag(d.dayId)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func yourFightsSection(payload: TournamentDayPayload) -> some View {
        let groups = trackedGroups(in: payload)
        if !groups.isEmpty {
            Section("Your fights today") {
                ForEach(groups) { group in
                    TrackedGroupCard(
                        group: group,
                        onTapFight: { fight in selectedMatName = fight.matName }
                    )
                }
            }
        }
    }

    private func matSection(payload: TournamentDayPayload) -> some View {
        Section("Mat") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(payload.mats) { mat in
                        MatChip(
                            name: mat.matName,
                            selected: (selectedMatName ?? payload.mats.first?.matName) == mat.matName
                        ) {
                            selectedMatName = mat.matName
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    @ViewBuilder
    private func matchesSection(payload: TournamentDayPayload) -> some View {
        let matName = selectedMatName ?? payload.mats.first?.matName
        if let matName, let mat = payload.mats.first(where: { $0.matName == matName }) {
            Section(matName) {
                if mat.matches.isEmpty {
                    Text("No fights scheduled.").foregroundStyle(.textSecondary)
                } else {
                    ForEach(mat.matches) { match in
                        MatMatchRow(
                            match: match,
                            isTracked: containsTracked(match)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Polling

    private func startPolling(tournamentId: Int, dayId: Int) {
        pollTask?.cancel()
        pollTask = Task {
            // Initial fetch
            await repo.loadTournamentDay(tournamentId: tournamentId, dayId: dayId)
            // Poll every 60s while view is on screen
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                await repo.loadTournamentDay(tournamentId: tournamentId, dayId: dayId)
            }
        }
    }

    // MARK: - Helpers

    private func currentDayPayload(tournament: Tournament, dayId: Int) -> TournamentDayPayload? {
        repo.tournamentDay["\(tournament.id):\(dayId)"]
    }

    private func containsTracked(_ match: MatMatch) -> Bool {
        match.competitors.contains { c in
            guard let name = c.name, let club = c.club else { return false }
            return tracking.matchesAnyTracked(name: name, team: club)
        }
    }

    /// Group upcoming fights by the tracked entity (athlete or team) that matched them.
    /// Each group is a collapsible card; an athlete + team tracked simultaneously may
    /// appear under both groups, which is fine — the user explicitly tracked both.
    private func trackedGroups(in payload: TournamentDayPayload) -> [TrackedGroup] {
        var byKey: [String: TrackedGroup] = [:]

        // Index tracked teams by lowercased name for fast lookup
        let trackedTeamLowers = tracking.trackedTeams.map { ($0.name, $0.name.lowercased()) }

        for mat in payload.mats {
            for m in mat.matches {
                guard !m.isComplete else { continue }
                let fight = TrackedFight(matName: mat.matName, match: m)

                for c in m.competitors {
                    guard let cName = c.name else { continue }
                    let cClubLower = (c.club ?? "").lowercased()

                    // 1. Athlete match — group key is the tracked athlete's display name
                    for ta in tracking.trackedAthletes
                    where TrackingStore.nameMatch(tracked: ta.name, against: cName) {
                        let key = "athlete:\(ta.name.lowercased())"
                        var g = byKey[key] ?? TrackedGroup(
                            id: key,
                            kind: .athlete,
                            title: ta.name,
                            subtitle: ta.team,
                            fights: []
                        )
                        if !g.fights.contains(fight) { g.fights.append(fight) }
                        byKey[key] = g
                    }

                    // 2. Team match — group key is the tracked team
                    for (display, lower) in trackedTeamLowers
                    where !lower.isEmpty &&
                          (cClubLower.contains(lower) || lower.contains(cClubLower)) {
                        let key = "team:\(lower)"
                        var g = byKey[key] ?? TrackedGroup(
                            id: key,
                            kind: .team,
                            title: display,
                            subtitle: nil,
                            fights: []
                        )
                        if !g.fights.contains(fight) { g.fights.append(fight) }
                        byKey[key] = g
                    }
                }
            }
        }

        return byKey.values
            .map { g -> TrackedGroup in
                var sorted = g
                sorted.fights.sort {
                    ($0.matName, $0.match.fight ?? 0) < ($1.matName, $1.match.fight ?? 0)
                }
                return sorted
            }
            .sorted { lhs, rhs in
                // Athletes first (more personal), then teams. Within each, alphabetical.
                if lhs.kind != rhs.kind { return lhs.kind == .athlete }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }
}

// MARK: - Subviews

private struct TrackedFight: Hashable {
    let matName: String
    let match: MatMatch
}

private enum TrackedGroupKind { case athlete, team }

private struct TrackedGroup: Identifiable {
    let id: String
    let kind: TrackedGroupKind
    let title: String
    let subtitle: String?
    var fights: [TrackedFight]

    var nextFight: TrackedFight? { fights.first }
}

/// Collapsible card per tracked athlete/team. Collapsed view shows next fight
/// summary; expanded shows all upcoming fights with tappable rows that jump to
/// the corresponding mat queue.
private struct TrackedGroupCard: View {
    let group: TrackedGroup
    let onTapFight: (TrackedFight) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.fights, id: \.self) { f in
                        AppHairline()
                        Button { onTapFight(f) } label: { fightRow(f) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: group.kind == .athlete ? "person.fill" : "person.3.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.textPrimary)
                if let next = group.nextFight {
                    Text(nextSummary(next))
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                } else if let sub = group.subtitle {
                    Text(sub).font(.caption).foregroundStyle(.textTertiary)
                }
            }

            Spacer()

            Text("\(group.fights.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.accent)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.accentWashLight)
                .clipShape(Capsule())

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    private func fightRow(_ f: TrackedFight) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.matName).font(.appBadge).foregroundStyle(.accent)
                Text("F\(f.match.fight.map(String.init) ?? "—")")
                    .font(.caption2).foregroundStyle(.textTertiary)
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(f.match.competitors.enumerated()), id: \.offset) { _, c in
                    Text(c.displayName).font(.caption).foregroundStyle(.textPrimary)
                }
                if let cat = f.match.category {
                    Text(cat).font(.caption2).foregroundStyle(.textTertiary)
                }
            }

            Spacer()

            if let when = f.match.when {
                Text(when).font(.caption).foregroundStyle(.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.textTertiary)
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    private func nextSummary(_ f: TrackedFight) -> String {
        var parts: [String] = []
        if let when = f.match.when { parts.append(when) }
        parts.append(f.matName)
        if let fight = f.match.fight { parts.append("Fight \(fight)") }
        return parts.joined(separator: " · ")
    }
}

private struct MatChip: View {
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(selected ? Color.accent : Color.cardElevated)
                .foregroundStyle(selected ? .white : .textPrimary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(selected ? Color.accent : Color.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MatMatchRow: View {
    let match: MatMatch
    let isTracked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("F\(match.fight.map(String.init) ?? "—")")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isTracked ? .accent : .textPrimary)
                if let when = match.when {
                    Text(when).font(.caption2).foregroundStyle(.textTertiary)
                }
                if let phase = match.phase {
                    Text(phase).font(.caption2).foregroundStyle(.textTertiary)
                }
            }
            .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(match.competitors.enumerated()), id: \.offset) { _, c in
                    HStack(spacing: 4) {
                        if let seed = c.seed {
                            Text("\(seed)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.textTertiary)
                                .frame(width: 18, alignment: .trailing)
                        } else {
                            Spacer().frame(width: 18)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.displayName).font(.callout).foregroundStyle(.textPrimary)
                            if let club = c.club, !club.isEmpty {
                                Text(club).font(.caption2).foregroundStyle(.textTertiary)
                            }
                        }
                    }
                }
                if let cat = match.category {
                    Text(cat).font(.caption2).foregroundStyle(.textTertiary).padding(.top, 2)
                }
            }

            Spacer()

            if match.isComplete {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.textTertiary)
            } else if match.isInProgress {
                Image(systemName: "play.circle.fill").foregroundStyle(.accent)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isTracked ? Color.accent.opacity(0.08) : Color.clear)
    }
}
