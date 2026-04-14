import SwiftUI

// MARK: - View mode

enum TrackingViewMode: String, CaseIterable {
    case teams    = "Teams"
    case athletes = "Athletes"
}

// MARK: - Removable item helper

private enum RemovableItem: Identifiable {
    case team(TrackedTeam)
    case athlete(TrackedAthlete)

    var id: String {
        switch self {
        case .team(let t):    return "team-\(t.id)"
        case .athlete(let a): return "athlete-\(a.id)"
        }
    }
    var displayName: String {
        switch self {
        case .team(let t):    return t.name
        case .athlete(let a): return a.name
        }
    }
}

// MARK: - Root view

struct TrackingRootView: View {

    @Environment(TrackingStore.self)      private var store
    @Environment(EventsRepository.self)  private var eventsRepo
    @Environment(BracketRepository.self) private var bracketRepo

    @State private var viewMode:    TrackingViewMode = .teams
    @State private var showAdd:     Bool             = false
    @State private var itemToRemove: RemovableItem?  = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Segmented toggle ───────────────────────────────────
                    Picker("View", selection: $viewMode.animation()) {
                        ForEach(TrackingViewMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    // ── Mode-specific tracked list ─────────────────────────
                    switch viewMode {
                    case .teams:    trackedTeamsSection
                    case .athletes: trackedAthletesSection
                    }

                    // ── Registrations (filtered by mode) ──────────────────
                    let hasTracked = viewMode == .teams
                        ? !store.trackedTeams.isEmpty
                        : !store.trackedAthletes.isEmpty

                    if !hasTracked {
                        emptyState
                    } else {
                        eventsSection
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("My Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").foregroundStyle(.gold)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTrackingSheet(
                    allTeams:    allTeamNames,
                    allAthletes: allAthleteNames,
                    initialMode: viewMode
                )
            }
            .confirmationDialog(
                "Remove from tracking?",
                isPresented: Binding(get: { itemToRemove != nil }, set: { if !$0 { itemToRemove = nil } }),
                presenting: itemToRemove
            ) { item in
                Button("Remove \(item.displayName)", role: .destructive) {
                    withAnimation {
                        switch item {
                        case .team(let t):
                            store.trackedTeams.removeAll { $0.id == t.id }
                        case .athlete(let a):
                            store.trackedAthletes.removeAll { $0.id == a.id }
                        }
                    }
                }
            } message: { item in
                Text("Stop tracking \"\(item.displayName)\"?")
            }
            .task { if bracketRepo.tournaments.isEmpty { await bracketRepo.loadTournaments() } }
        }
    }

    // MARK: - Tracked teams section

    private var trackedTeamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionLabel("Tracked Teams")
            if store.trackedTeams.isEmpty {
                AppCard {
                    HStack(spacing: 10) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(.white.opacity(0.2)).font(.title3)
                        Text("No teams added yet — tap + to add one")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.35))
                    }
                }
            } else {
                AppCard {
                    VStack(spacing: 0) {
                        ForEach(store.trackedTeams) { team in
                            Button { itemToRemove = .team(team) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.3.fill")
                                        .font(.caption).foregroundStyle(.gold.opacity(0.7)).frame(width: 20)
                                    Text(team.name)
                                        .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Image(systemName: "minus.circle")
                                        .font(.subheadline).foregroundStyle(.white.opacity(0.2))
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if team.id != store.trackedTeams.last?.id {
                                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tracked athletes section

    private var trackedAthletesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionLabel("Tracked Athletes")
            if store.trackedAthletes.isEmpty {
                AppCard {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill.badge.plus")
                            .foregroundStyle(.white.opacity(0.2)).font(.title3)
                        Text("No athletes added yet — tap + to add one")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.35))
                    }
                }
            } else {
                AppCard {
                    VStack(spacing: 0) {
                        ForEach(store.trackedAthletes) { athlete in
                            Button { itemToRemove = .athlete(athlete) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .font(.caption).foregroundStyle(.gold.opacity(0.7)).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(athlete.name)
                                            .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                                        if let team = athlete.team {
                                            Text(team).font(.caption).foregroundStyle(.white.opacity(0.4))
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "minus.circle")
                                        .font(.subheadline).foregroundStyle(.white.opacity(0.2))
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if athlete.id != store.trackedAthletes.last?.id {
                                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Events section (filtered by mode)

    private var eventsSection: some View {
        let matched = eventsWithRegistrations
        let modeLabel = viewMode == .teams ? "Team" : "Athlete"
        return VStack(alignment: .leading, spacing: 20) {
            AppSectionLabel("\(modeLabel) Registrations · \(matched.count) event\(matched.count == 1 ? "" : "s")")
            if matched.isEmpty {
                AppCard {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(.white.opacity(0.2)).font(.title3)
                        Text(viewMode == .teams
                            ? "No tracked teams registered for upcoming events"
                            : "No tracked athletes registered for upcoming events")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.35))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(matched, id: \.event.id) { item in
                    TrackedEventCard(
                        event:             item.event,
                        registrations:     item.registrations,
                        tournaments:       bracketRepo.tournaments,
                        scheduleMatches:   bracketRepo.schedules[store.linkedTournamentId(for: item.event.id) ?? -1] ?? [],
                        isLoadingSchedule: bracketRepo.loadingSchedules.contains(store.linkedTournamentId(for: item.event.id) ?? -1),
                        scheduleError:     bracketRepo.scheduleErrors[store.linkedTournamentId(for: item.event.id) ?? -1],
                        onLinkTournament:  { tid in store.linkTournament(tid, to: item.event.id) },
                        onUnlink: {
                            if let tid = store.linkedTournamentId(for: item.event.id) { bracketRepo.clearSchedule(for: tid) }
                            store.unlinkTournament(from: item.event.id)
                        },
                        onLoadSchedule: {
                            guard let tid = store.linkedTournamentId(for: item.event.id) else { return }
                            let names = trackedNames
                            Task { await bracketRepo.loadSchedule(tournamentId: tid, names: names) }
                        },
                        onRefreshSchedule: {
                            guard let tid = store.linkedTournamentId(for: item.event.id) else { return }
                            bracketRepo.clearSchedule(for: tid)
                            let names = trackedNames
                            Task { await bracketRepo.loadSchedule(tournamentId: tid, names: names) }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Empty state (mode-aware)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: viewMode == .teams ? "person.3.sequence.fill" : "person.fill.badge.plus")
                .font(.system(size: 44)).foregroundStyle(.white.opacity(0.1))
            Text(viewMode == .teams ? "Track your team" : "Track athletes")
                .font(.title3).fontWeight(.semibold).foregroundStyle(.white.opacity(0.5))
            Text(viewMode == .teams
                ? "Add a team to see all their athletes across upcoming events."
                : "Add individual athletes to follow their registrations and mat assignments.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.3)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: - Computed helpers

    private var eventsWithRegistrations: [(event: BJJEvent, registrations: [(athlete: Athlete, division: Division)])] {
        let now = Date()
        let upcoming: [BJJEvent] = eventsRepo.events
            .filter { ($0.endDateParsed ?? .distantPast) >= now }
            .sorted { ($0.startDateParsed ?? .distantFuture) < ($1.startDateParsed ?? .distantFuture) }
        var result: [(event: BJJEvent, registrations: [(athlete: Athlete, division: Division)])] = []
        for event in upcoming {
            let regs: [(athlete: Athlete, division: Division)]
            switch viewMode {
            case .teams:    regs = store.teamMatchingRegistrations(in: event)
            case .athletes: regs = store.athleteMatchingRegistrations(in: event)
            }
            if !regs.isEmpty { result.append((event: event, registrations: regs)) }
        }
        return result
    }

    private var trackedNames: [String] {
        store.trackedAthletes.map { $0.name } + store.trackedTeams.map { $0.name }
    }

    private var allTeamNames: [String] {
        Array(Set(eventsRepo.events.flatMap { $0.divisions.flatMap { $0.athletes.map { $0.team } } })).sorted()
    }

    private var allAthleteNames: [(name: String, team: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for event in eventsRepo.events {
            for division in event.divisions {
                for athlete in division.athletes {
                    let key = athlete.name.lowercased()
                    if !seen.contains(key) { seen.insert(key); result.append((athlete.name, athlete.team)) }
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }
}

// MARK: - Unified add sheet

struct AddTrackingSheet: View {

    let allTeams:    [String]
    let allAthletes: [(name: String, team: String)]
    let initialMode: TrackingViewMode

    @Environment(TrackingStore.self)       private var store
    @Environment(AthletesRepository.self) private var athletesRepo
    @Environment(\.dismiss)                private var dismiss

    @State private var mode:       TrackingViewMode = .teams
    @State private var searchText: String           = ""

    // Local event-based results
    private var localResults: [(name: String, team: String)] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        switch mode {
        case .teams:
            return allTeams
                .filter { $0.lowercased().contains(q) && !store.isTrackingTeam($0) }
                .map { ($0, "") }
        case .athletes:
            return allAthletes
                .filter { $0.name.lowercased().contains(q) && !store.isTrackingAthlete(name: $0.name) }
        }
    }

    // IBJJF ranked athlete results (instant local search)
    private var rankedResults: [RankedAthlete] {
        guard mode == .athletes else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return [] } // need at least 3 chars for ranking search
        return athletesRepo.search(name: q, limit: 30)
            .filter { !store.isTrackingAthlete(name: $0.name) }
    }

    private var canAddCustom: Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return false }
        return mode == .teams ? !store.isTrackingTeam(q) : !store.isTrackingAthlete(name: q)
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Mode picker ──────────────────────────────────────────
                Section {
                    Picker("Type", selection: $mode) {
                        ForEach(TrackingViewMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 4)
                }

                // ── Search field ─────────────────────────────────────────
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
                        TextField(
                            mode == .teams ? "Enter any team name" : "Search athlete name",
                            text: $searchText
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                } footer: {
                    if mode == .athletes && !athletesRepo.athletes.isEmpty {
                        Text("\(athletesRepo.athletes.count) ranked athletes available · results appear as you type")
                            .font(.caption)
                    }
                }

                // ── Add custom name ──────────────────────────────────────
                if canAddCustom {
                    Section {
                        Button {
                            let q = searchText.trimmingCharacters(in: .whitespaces)
                            if mode == .teams { store.addTeam(q) }
                            else              { store.addAthlete(name: q, team: nil) }
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.gold)
                                Text("Add \"\(searchText.trimmingCharacters(in: .whitespaces))\"")
                                    .fontWeight(.medium).foregroundStyle(.primary)
                                Spacer()
                                Text(mode == .teams ? "TEAM" : "ATHLETE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.gold.opacity(0.7))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.gold.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // ── IBJJF ranked athletes (instant) ─────────────────────
                if !rankedResults.isEmpty {
                    Section("IBJJF Ranked Athletes") {
                        ForEach(rankedResults) { ranked in
                            Button {
                                store.addAthlete(name: ranked.name, team: ranked.team)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(ranked.name).foregroundStyle(.primary).fontWeight(.medium)
                                        Text(ranked.team).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(ranked.belt.capitalized)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.7))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.beltColor(ranked.belt).opacity(0.3))
                                            .clipShape(Capsule())
                                        if let rank = ranked.rank {
                                            Text("#\(rank) · \(ranked.points) pts")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Registered in upcoming events ────────────────────────
                if !localResults.isEmpty {
                    Section("Registered in upcoming events") {
                        ForEach(localResults, id: \.name) { entry in
                            Button {
                                if mode == .teams { store.addTeam(entry.name) }
                                else              { store.addAthlete(name: entry.name, team: entry.team) }
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: mode == .teams ? "person.3.fill" : "person.fill")
                                        .font(.caption)
                                        .foregroundStyle(mode == .teams ? .gold.opacity(0.8) : .white.opacity(0.5))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name).foregroundStyle(.primary)
                                        if !entry.team.isEmpty {
                                            Text(entry.team).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add \(mode == .teams ? "Team" : "Athlete")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear { mode = initialMode }
    }
}

// MARK: - Tracked event card

struct TrackedEventCard: View {

    let event:             BJJEvent
    let registrations:     [(athlete: Athlete, division: Division)]
    let tournaments:       [Tournament]
    let scheduleMatches:   [ScheduleMatch]
    let isLoadingSchedule: Bool
    let scheduleError:     String?
    let onLinkTournament:  (Int) -> Void
    let onUnlink:          () -> Void
    let onLoadSchedule:    () -> Void
    let onRefreshSchedule: () -> Void

    @Environment(TrackingStore.self) private var store
    @State private var expanded           = true
    @State private var showTournamentPicker = false

    private var linkedTournamentId: Int? { store.linkedTournamentId(for: event.id) }
    private var linkedTournamentName: String? {
        guard let tid = linkedTournamentId else { return nil }
        return tournaments.first { $0.id == tid }?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────────
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(dateLabel).font(.caption).foregroundStyle(.white.opacity(0.4))
                            Text("·").foregroundStyle(.white.opacity(0.2))
                            Text(event.city).font(.caption).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text("\(registrations.count)")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.gold)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.gold.opacity(0.12)).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.gold.opacity(0.25), lineWidth: 1))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                tournamentLinkBar
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)

                VStack(spacing: 0) {
                    ForEach(Array(registrations.enumerated()), id: \.offset) { i, reg in
                        let matchesForAthlete = scheduleMatches.filter {
                            ($0.athleteName?.lowercased() ?? "") == reg.athlete.name.lowercased()
                        }
                        TrackedAthleteRow(athlete: reg.athlete, division: reg.division, scheduleMatches: matchesForAthlete)
                        if i < registrations.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.gold.opacity(0.2), lineWidth: 1))
        .sheet(isPresented: $showTournamentPicker) {
            TournamentPickerSheet(
                tournaments: tournaments,
                currentId:   linkedTournamentId,
                onSelect:    { id in onLinkTournament(id); showTournamentPicker = false }
            )
        }
    }

    @ViewBuilder
    private var tournamentLinkBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.caption2)
                .foregroundStyle(linkedTournamentId != nil ? .gold : .white.opacity(0.25))

            if let name = linkedTournamentName {
                Text(name).font(.caption).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).truncationMode(.tail)
            } else {
                Text(tournaments.isEmpty ? "Loading tournaments…" : "Link bracket tournament")
                    .font(.caption).foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            if linkedTournamentId != nil {
                if isLoadingSchedule {
                    ProgressView().tint(.gold).scaleEffect(0.7)
                } else if scheduleMatches.isEmpty {
                    Button(action: onLoadSchedule) {
                        Text("Load Schedule")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.gold)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.gold.opacity(0.12)).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.gold.opacity(0.3), lineWidth: 1))
                    }.buttonStyle(.plain)
                } else {
                    Button(action: onRefreshSchedule) {
                        Image(systemName: "arrow.clockwise").font(.caption2).foregroundStyle(.gold.opacity(0.7))
                    }.buttonStyle(.plain)
                }
                Button(action: { showTournamentPicker = true }) {
                    Image(systemName: "pencil").font(.caption2).foregroundStyle(.white.opacity(0.3))
                }.buttonStyle(.plain)
            } else {
                Button(action: { showTournamentPicker = true }) {
                    Text("Link")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.07)).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(tournaments.isEmpty)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var dateLabel: String {
        guard let s = event.startDateParsed else { return event.startDate }
        let f = DateFormatter.display
        if event.startDate == event.endDate { return f.string(from: s) }
        guard let e = event.endDateParsed else { return f.string(from: s) }
        return "\(f.string(from: s)) – \(f.string(from: e))"
    }
}

// MARK: - Tracked athlete row

struct TrackedAthleteRow: View {
    let athlete:        Athlete
    let division:       Division
    let scheduleMatches: [ScheduleMatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle().fill(Color.beltColor(division.belt)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(athlete.name)
                        .font(.subheadline).fontWeight(.medium).foregroundStyle(.white.opacity(0.9))
                    Text(athlete.team).font(.caption).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Text(divisionShort)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.white.opacity(0.07)).clipShape(Capsule())
            }

            if scheduleMatches.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Color.white.opacity(0.15)).frame(width: 5, height: 5)
                    Text("No bracket assigned yet").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }.padding(.leading, 20)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(scheduleMatches) { match in ScheduleMatchRow(match: match) }
                }.padding(.leading, 20)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var divisionShort: String { "\(division.belt.capitalized) · \(division.weightClass)" }
}

// MARK: - Schedule match row

struct ScheduleMatchRow: View {
    let match: ScheduleMatch

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if let mat = match.mat, !mat.isEmpty {
                    Text(mat).font(.system(size: 10, weight: .bold)).foregroundStyle(.gold)
                }
                if let fight = match.fight {
                    Text("Fight \(fight)").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.gold.opacity(0.08)).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.gold.opacity(0.2), lineWidth: 1))

            if let when = match.when, !when.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.system(size: 9))
                    Text(when).font(.system(size: 10))
                }.foregroundStyle(.white.opacity(0.45))
            }

            if let opponent = match.opponent, !opponent.isEmpty {
                Text("vs \(opponent)")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1).truncationMode(.tail)
            }

            Spacer()

            Text(roundLabel)
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.white.opacity(0.05)).clipShape(Capsule())
        }
    }

    private var roundLabel: String {
        switch match.round {
        case 1: return "R1"
        case 2: return "R2"
        case 3: return "Qtrs"
        case 4: return "Semis"
        case 5: return "Final"
        default: return "R\(match.round)"
        }
    }
}

// MARK: - Tournament picker sheet

struct TournamentPickerSheet: View {
    let tournaments: [Tournament]
    let currentId:   Int?
    let onSelect:    (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Tournament] {
        search.isEmpty ? tournaments : tournaments.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { t in
                Button { onSelect(t.id) } label: {
                    HStack {
                        Text(t.name).foregroundStyle(.primary)
                        Spacer()
                        if t.id == currentId {
                            Image(systemName: "checkmark").foregroundStyle(.gold).font(.caption)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search tournaments")
            .navigationTitle("Select Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
