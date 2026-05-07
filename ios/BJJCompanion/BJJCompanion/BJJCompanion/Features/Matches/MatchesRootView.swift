import SwiftUI

/// Live mat-queue view for tournament day. Replaces the legacy Brackets tab as
/// the primary view; the bracket-tree picker is still reachable via a toolbar
/// menu for users who want to plan ahead.
struct MatchesRootView: View {

    @Environment(BracketRepository.self) private var repo
    @Environment(TrackingStore.self)     private var tracking
    @Environment(EventsRepository.self)  private var eventsRepo

    @State private var selectedTournament: Tournament?
    @State private var selectedDayId: Int?
    @State private var selectedMatName: String?
    @State private var pollTask: Task<Void, Never>?
    /// Collapsed by default — multi-team users would otherwise see a long
    /// list of TrackedGroupCards before reaching the day/mat/match selectors.
    @State private var yourFightsExpanded: Bool = false

    /// Tournaments filtered to drop ones whose matching IBJJF event has already
    /// ended. Cross-references by name against `EventsRepository` since the
    /// Tournament model from the proxy carries no date. Tournaments with no
    /// event match are kept ONLY if the events feed itself hasn't loaded yet —
    /// once events are present we trust the cross-reference and drop unknowns,
    /// which is what filters out long-finished compsystem tournaments that
    /// IBJJF no longer lists.
    private var upcomingTournaments: [Tournament] {
        let now = Date()
        let haveEvents = !eventsRepo.events.isEmpty
        return repo.tournaments.filter { t in
            guard let event = matchingEvent(for: t) else {
                // No event match: keep only if events haven't loaded yet.
                return !haveEvents
            }
            return (event.endDateParsed ?? .distantFuture) >= now
        }
    }

    private func matchingEvent(for t: Tournament) -> BJJEvent? {
        let needleTokens = Self.significantTokens(t.name)
        guard !needleTokens.isEmpty else { return nil }
        // Pick the BEST match (highest Jaccard similarity) — not just the first
        // that crosses a threshold. Threshold of 0.7 is strict enough that
        // "Atlanta Spring 2026" won't false-match "Boston Spring 2026" (whose
        // Jaccard = 0.6) while still allowing minor token diffs (e.g. Gi vs
        // No-Gi versions of the same event).
        var best: (event: BJJEvent, score: Double)?
        for ev in eventsRepo.events {
            let hayTokens = Self.significantTokens(ev.name)
            guard !hayTokens.isEmpty else { continue }
            let intersection = needleTokens.intersection(hayTokens).count
            let union        = needleTokens.union(hayTokens).count
            let jaccard      = Double(intersection) / Double(union)
            if jaccard >= 0.7, jaccard > (best?.score ?? 0) {
                best = (ev, jaccard)
            }
        }
        return best?.event
    }

    /// Lowercased, punctuation-stripped, stopword-filtered tokens used for
    /// fuzzy event/tournament name matching. Stopwords cover IBJJF boilerplate
    /// that appears inconsistently across compsystem vs the events feed.
    private static func significantTokens(_ s: String) -> Set<String> {
        let stop: Set<String> = [
            "ibjjf", "jiu", "jitsu", "jiu-jitsu", "jiujitsu",
            "championship", "championships", "tournament", "open",
            "the", "of", "and", "&", "no-gi", "nogi", "gi"
        ]
        let cleaned = s.lowercased().unicodeScalars.map { sc -> Character in
            CharacterSet.alphanumerics.contains(sc) ? Character(sc) : " "
        }
        return Set(String(cleaned).split(separator: " ").map(String.init).filter {
            !$0.isEmpty && !stop.contains($0) && $0.count > 1
        })
    }

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
                .task {
                    if repo.tournaments.isEmpty { await repo.loadTournaments() }
                    if eventsRepo.events.isEmpty { await eventsRepo.refresh() }
                }
                .onDisappear { pollTask?.cancel(); pollTask = nil }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        Form {
            tournamentSection

            if let tournament = selectedTournament {
                if let rawDays = repo.tournamentDays[tournament.id], !rawDays.isEmpty {
                    let days = chronologicallyOrdered(rawDays)

                    // Order: Your fights (most personal) → Day picker → Mat
                    // picker → Match list. The day picker used to sit at the
                    // top, which made the weekday chips read like a top-level
                    // filter on the whole screen — confusing because the
                    // "Your fights" aggregator already spans every day.
                    // `yourFightsSection` is a no-op when no tracked groups
                    // appear in any loaded payload, so it doesn't waste space.
                    yourFightsSection(tournament: tournament, days: days)
                    daySection(days: days, tournament: tournament)

                    if let dayId = selectedDayId, let payload = currentDayPayload(tournament: tournament, dayId: dayId) {
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
                    ForEach(upcomingTournaments) { t in
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
                        guard let raw = repo.tournamentDays[t.id], !raw.isEmpty else { return }
                        let days = chronologicallyOrdered(raw)
                        // Pre-fetch every day so "Your fights" can aggregate
                        // across the whole tournament (a tracked athlete might
                        // not fight today). Cheap — proxy caches per-day.
                        await withTaskGroup(of: Void.self) { group in
                            for d in days {
                                group.addTask { await repo.loadTournamentDay(tournamentId: t.id, dayId: d.dayId) }
                            }
                        }
                        // Auto-select the day where the user's next tracked
                        // fight lives; falls back to the chronologically
                        // earliest day if no tracked athletes / nothing matched.
                        let preferred = dayWithNextTrackedFight(tournamentId: t.id, days: days)
                            ?? days.first!.dayId
                        selectedDayId = preferred
                        startPolling(tournamentId: t.id, dayId: preferred)
                    }
                }

                // Friendly notice so users understand why their tournament may
                // not appear yet — brackets are typically published 1–3 days
                // before the event date.
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.textTertiary)
                        .font(.caption)
                    Text("Tournaments appear once brackets are published — usually 1–3 days before the event. Past events drop off automatically.")
                        .font(.caption)
                        .foregroundStyle(.textTertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func daySection(days: [TournamentDay], tournament: Tournament) -> some View {
        let binding = Binding(
            get: { selectedDayId ?? days.first?.dayId ?? 0 },
            set: { newValue in
                selectedDayId = newValue
                selectedMatName = nil
                startPolling(tournamentId: tournament.id, dayId: newValue)
            }
        )
        // Segmented picker fits ≤3 chips cleanly. Worlds/Brasileiro run
        // 7–10 days, so beyond that we switch to a single-row menu picker —
        // taps reveal the full list as a dropdown without taking up vertical
        // space in the form. The "Day" section header is omitted because
        // the picker label already conveys it.
        return Section {
            if days.count <= 3 {
                Picker("Day", selection: binding) {
                    ForEach(days) { d in
                        Text(d.shortLabel).tag(d.dayId)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Day", selection: binding) {
                    ForEach(days) { d in
                        Text(dayMenuLabel(d)).tag(d.dayId)
                    }
                }
                .pickerStyle(.menu)
                .tint(.accent)
            }
        }
    }

    /// Returns days in true chronological order. The proxy preserves DOM
    /// order going forward, but compsystem occasionally assigned dayIds in
    /// reverse so older cache entries (and any lingering ascending-id sort)
    /// can show the calendar backwards. We detect reversed weekday sequences
    /// and flip the array so the picker always reads earliest → latest.
    private func chronologicallyOrdered(_ days: [TournamentDay]) -> [TournamentDay] {
        guard days.count >= 2 else { return days }
        let nums = days.map { weekdayNumber($0.displayWeekday) }
        guard nums.allSatisfy({ $0 != nil }) else { return days }

        // Vote on direction by looking at consecutive deltas mod 7.
        // +1 = forward chronological, +6 (-1 mod 7) = reversed.
        var forward = 0, reverse = 0
        for i in 0..<(nums.count - 1) {
            let delta = ((nums[i + 1]! - nums[i]!) % 7 + 7) % 7
            if delta == 1 { forward += 1 }
            else if delta == 6 { reverse += 1 }
        }
        return reverse > forward ? Array(days.reversed()) : days
    }

    /// Mon=1 ... Sun=7, matching ISO weekday numbering. Returns nil for
    /// labels we can't translate.
    private func weekdayNumber(_ wd: String?) -> Int? {
        switch (wd ?? "").lowercased() {
        case "monday":    return 1
        case "tuesday":   return 2
        case "wednesday": return 3
        case "thursday":  return 4
        case "friday":    return 5
        case "saturday":  return 6
        case "sunday":    return 7
        default:          return nil
        }
    }

    /// Full-day label for the menu picker — "Sunday · 09:30 AM" or just the
    /// weekday when start time is missing. Falls back to the raw label so
    /// nothing renders blank for unknown locales.
    private func dayMenuLabel(_ d: TournamentDay) -> String {
        let weekday = d.displayWeekday ?? d.label.split(separator: " ").first.map(String.init) ?? "Day \(d.dayId)"
        if let st = d.startTime, !st.isEmpty {
            return "\(weekday) · \(st)"
        }
        return weekday
    }

    @ViewBuilder
    private func yourFightsSection(tournament: Tournament, days: [TournamentDay]) -> some View {
        // Aggregate across every loaded day so the user sees Saturday's
        // fight on Friday — without having to discover the day picker.
        let payloads = days.compactMap { repo.tournamentDay["\(tournament.id):\($0.dayId)"] }
        let groups = trackedGroups(in: payloads, days: days)
        if !groups.isEmpty {
            // Collapsed by default so multi-team users aren't buried under
            // a long card list before they see the day/mat/match controls.
            // The header still surfaces the total count so it's obvious how
            // many tracked items have fights without expanding.
            let totalFights = groups.reduce(0) { $0 + $1.fights.count }
            Section {
                DisclosureGroup(isExpanded: $yourFightsExpanded) {
                    ForEach(groups) { group in
                        TrackedGroupCard(
                            group: group,
                            onTapFight: { fight in
                                // Jump to the fight's day + mat in one tap.
                                if selectedDayId != fight.dayId {
                                    selectedDayId = fight.dayId
                                    startPolling(tournamentId: tournament.id, dayId: fight.dayId)
                                }
                                selectedMatName = fight.matName
                            }
                        )
                    }
                } label: {
                    HStack {
                        Text("Your Athletes Fights")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        Text("\(totalFights)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentWashLight)
                            .clipShape(Capsule())
                    }
                }
                .tint(.accent)
            }
        }
    }

    private func matSection(payload: TournamentDayPayload) -> some View {
        Section("Mat") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(payload.mats) { mat in
                        MatChip(
                            name: mat.matName.displayMatName,
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
            Section(matName.displayMatName) {
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
    /// Scans every loaded tournament day so a Saturday fight shows up on Friday.
    private func trackedGroups(in payloads: [TournamentDayPayload], days: [TournamentDay]) -> [TrackedGroup] {
        var byKey: [String: TrackedGroup] = [:]

        // Index tracked teams by lowercased name for fast lookup
        let trackedTeamLowers = tracking.trackedTeams.map { ($0.name, $0.name.lowercased()) }

        // Day weekday lookup so the row badge can read "Sat · Mat 7 · F4".
        let weekdayByDayId: [Int: String] = Dictionary(
            uniqueKeysWithValues: days.map { ($0.dayId, ($0.displayWeekday ?? "").prefix(3).description) }
        )
        // Map dayId to its chronological index so fights sort earliest-first
        // even when compsystem assigned dayIds in reverse order.
        let chronoIndexByDayId: [Int: Int] = Dictionary(
            uniqueKeysWithValues: days.enumerated().map { ($0.element.dayId, $0.offset) }
        )

        for payload in payloads {
            let dayWeekday = weekdayByDayId[payload.dayId] ?? ""
            for mat in payload.mats {
                for m in mat.matches {
                    guard !m.isComplete else { continue }
                    let fight = TrackedFight(
                        dayId:      payload.dayId,
                        dayWeekday: dayWeekday,
                        matName:    mat.matName,
                        match:      m
                    )

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
        }

        return byKey.values
            .map { g -> TrackedGroup in
                var sorted = g
                sorted.fights.sort {
                    let li = chronoIndexByDayId[$0.dayId] ?? .max
                    let ri = chronoIndexByDayId[$1.dayId] ?? .max
                    // Sort by: day → time → fight number → mat. Time-first
                    // ordering matters for team groups whose collapsed header
                    // displays the first fight as a "next up" summary; the
                    // earliest team fight should win, not whichever fight is
                    // alphabetically first by mat name. Missing `when` sorts
                    // last within the same day.
                    let lt = $0.match.when ?? "99:99"
                    let rt = $1.match.when ?? "99:99"
                    return (li, lt, $0.match.fight ?? 0, $0.matName)
                        < (ri, rt, $1.match.fight ?? 0, $1.matName)
                }
                return sorted
            }
            .sorted { lhs, rhs in
                // Athletes first (more personal), then teams. Within each, alphabetical.
                if lhs.kind != rhs.kind { return lhs.kind == .athlete }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// Day id with the earliest tracked-athlete fight, or nil if no tracked
    /// athlete/team appears on any loaded day. Used to default-select the day
    /// where the user's first fight lives instead of the calendar's first day.
    private func dayWithNextTrackedFight(tournamentId: Int, days: [TournamentDay]) -> Int? {
        let payloads = days.compactMap { repo.tournamentDay["\(tournamentId):\($0.dayId)"] }
        guard !payloads.isEmpty else { return nil }
        let groups = trackedGroups(in: payloads, days: days)
        return groups.first?.fights.first?.dayId
    }
}

// MARK: - Subviews

// MARK: - Mat name display
//
// Compsystem returns mat labels in the venue's local language. Brazilian
// events show "Área 1", French shows "Tapis", etc. Normalize to "Mat N" for
// display so the section header / chip / fight row read consistently — the
// raw `matName` remains the canonical id we filter by.

extension String {
    /// Returns this mat label rewritten to "Mat N" if the prefix matches a
    /// known foreign synonym; otherwise returns the original string unchanged.
    var displayMatName: String {
        let synonyms = ["área", "area", "tatame", "tapis", "aire", "tappeto", "matte", "マット"]
        let trimmed = trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        for syn in synonyms where lower.hasPrefix(syn) {
            // Pull whatever digits / suffix follow the prefix.
            let rest = trimmed.dropFirst(syn.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? "Mat" : "Mat \(rest)"
        }
        return trimmed
    }
}

private struct TrackedFight: Hashable {
    let dayId: Int
    let dayWeekday: String   // "Fri" / "Sat" / "Sun" — empty when unknown
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
                // Only athletes get a "next fight" summary in the collapsed
                // header — for teams the row count badge is enough, since
                // surfacing one specific athlete's time/mat under the team
                // name reads as if that's the team's "next fight" overall,
                // which is misleading. Teams fall back to the subtitle.
                if group.kind == .athlete, let next = group.nextFight {
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
                if !f.dayWeekday.isEmpty {
                    Text(f.dayWeekday.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.textTertiary)
                }
                Text(f.matName.displayMatName).font(.appBadge).foregroundStyle(.accent)
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
        if !f.dayWeekday.isEmpty { parts.append(f.dayWeekday) }
        if let when = f.match.when { parts.append(when) }
        parts.append(f.matName.displayMatName)
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
