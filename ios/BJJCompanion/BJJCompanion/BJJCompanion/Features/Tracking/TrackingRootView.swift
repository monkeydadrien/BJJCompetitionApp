import SwiftUI
import UIKit

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
                VStack(alignment: .leading, spacing: Spacing.xl - 4) {

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
                .padding(Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("My Team")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            .sheet(isPresented: $showAdd) {
                AddTrackingSheet(initialMode: viewMode)
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
        VStack(alignment: .leading, spacing: Spacing.md - 2) {
            AppSectionLabel("Tracked Teams")
            if store.trackedTeams.isEmpty {
                emptyAddCard(
                    title: "Tap to add a team",
                    leadingIcon: "person.3.fill"
                )
            } else {
                AppCard {
                    VStack(spacing: 0) {
                        ForEach(store.trackedTeams) { team in
                            trackedRow(
                                icon: "person.3.fill",
                                name: team.name,
                                onTap: { itemToRemove = .team(team) }
                            )
                            AppHairline()
                        }
                        addRow(label: "Add team")
                    }
                }
            }
        }
    }

    // MARK: - Tracked athletes section

    private var trackedAthletesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md - 2) {
            AppSectionLabel("Tracked Athletes")
            if store.trackedAthletes.isEmpty {
                emptyAddCard(
                    title: "Tap to add an athlete",
                    leadingIcon: "person.fill.badge.plus"
                )
            } else {
                AppCard {
                    VStack(spacing: 0) {
                        ForEach(store.trackedAthletes) { athlete in
                            Button { itemToRemove = .athlete(athlete) } label: {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                        .foregroundStyle(.accent.opacity(0.7))
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(athlete.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.textPrimary.opacity(0.9))
                                        if let team = athlete.team, !team.isEmpty {
                                            Text(team)
                                                .font(.caption)
                                                .foregroundStyle(.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "minus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.textQuaternary)
                                        .accessibilityLabel("Remove")
                                }
                                .padding(.vertical, Spacing.md - 2)
                            }
                            .buttonStyle(.plain)

                            AppHairline()
                        }
                        addRow(label: "Add athlete")
                    }
                }
            }
        }
    }

    // MARK: - Reusable row builders

    private func emptyAddCard(title: String, leadingIcon: String) -> some View {
        Button { showAdd = true } label: {
            AppCard {
                HStack(spacing: Spacing.md - 2) {
                    Image(systemName: leadingIcon)
                        .foregroundStyle(.accent.opacity(0.7))
                        .font(.title3)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.textSecondary)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Add panel")
    }

    private func trackedRow(icon: String, name: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.accent.opacity(0.7))
                    .frame(width: 20)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.textPrimary.opacity(0.9))
                Spacer()
                Image(systemName: "minus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.textQuaternary)
                    .accessibilityLabel("Remove")
            }
            .padding(.vertical, Spacing.md - 2)
        }
        .buttonStyle(.plain)
    }

    private func addRow(label: String) -> some View {
        Button { showAdd = true } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.accent)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.accent)
                Spacer()
            }
            .padding(.vertical, Spacing.md - 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Events section (filtered by mode)

    private var eventsSection: some View {
        let matched = eventsWithRegistrations
        let modeLabel = viewMode == .teams ? "Team" : "Athlete"
        return VStack(alignment: .leading, spacing: Spacing.xl - 4) {
            AppSectionLabel("\(modeLabel) Registrations · \(matched.count) event\(matched.count == 1 ? "" : "s")")
            if matched.isEmpty {
                AppCard {
                    HStack(spacing: Spacing.md - 2) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(.textQuaternary)
                            .font(.title3)
                        Text(viewMode == .teams
                            ? "No tracked teams registered for upcoming events"
                            : "No tracked athletes registered for upcoming events")
                            .font(.subheadline)
                            .foregroundStyle(.textTertiary)
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
    //
    // Apple HIG: empty states should explain what the user can do AND offer
    // the action. Adding the explicit CTA below the description converts
    // "what is this screen for?" into "let me try it."

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: viewMode == .teams ? "person.3.sequence.fill" : "person.fill.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.accent.opacity(0.55))
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, Spacing.xs)
            Text(viewMode == .teams ? "Track your team" : "Track athletes")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.textPrimary)
            Text(viewMode == .teams
                ? "Add a team to see all their athletes across upcoming events."
                : "Add individual athletes to follow their registrations and mat assignments.")
                .font(.subheadline)
                .foregroundStyle(.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            Button {
                showAdd = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(viewMode == .teams ? "Add team" : "Add athlete")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.black)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md - 2)
                .background(Color.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
}

// MARK: - Unified add sheet

struct AddTrackingSheet: View {

    let initialMode: TrackingViewMode

    @Environment(TrackingStore.self)      private var store
    @Environment(AthletesRepository.self) private var athletesRepo
    @Environment(\.dismiss)               private var dismiss

    @State private var mode:       TrackingViewMode = .teams
    @State private var searchText: String           = ""

    private var canAdd: Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return false }
        return mode == .teams ? !store.isTrackingTeam(q) : !store.isTrackingAthlete(name: q)
    }

    private var athleteSuggestions: [RegistryAthlete] {
        guard mode == .athletes else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return athletesRepo.search(query: q, limit: 10)
            .filter { !store.isTrackingAthlete(name: $0.name) }
    }

    private var teamSuggestions: [String] {
        guard mode == .teams else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 1 else { return [] }
        return athletesRepo.searchTeams(query: q, limit: 10)
            .filter { !store.isTrackingTeam($0) }
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
                    .padding(.vertical, Spacing.xs)
                }

                // ── Name field ───────────────────────────────────────────
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        TextField(
                            mode == .teams ? "Team name" : "Athlete full name",
                            text: $searchText
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                } footer: {
                    Text(mode == .teams
                        ? "Matches any athlete whose team name contains this text."
                        : "Pick from suggestions below, or add a custom name if yours isn't listed.")
                        .font(.caption)
                }

                // ── Suggestions from athlete registry ────────────────────
                if !athleteSuggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(athleteSuggestions) { hit in
                            Button {
                                store.addAthlete(name: hit.name, team: hit.team, bjjcsId: hit.id)
                                dismiss()
                            } label: {
                                HStack(spacing: Spacing.md - 2) {
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                        .foregroundStyle(.accent.opacity(0.7))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hit.name).foregroundStyle(.primary)
                                        if !hit.team.isEmpty {
                                            Text(hit.team)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // ── Team suggestions derived from athlete registry ───────
                if !teamSuggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(teamSuggestions, id: \.self) { team in
                            Button {
                                store.addTeam(team)
                                dismiss()
                            } label: {
                                HStack(spacing: Spacing.md - 2) {
                                    Image(systemName: "person.3.fill")
                                        .font(.caption)
                                        .foregroundStyle(.accent.opacity(0.7))
                                        .frame(width: 18)
                                    Text(team).foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // ── Add button ───────────────────────────────────────────
                if canAdd {
                    Section {
                        Button {
                            let q = searchText.trimmingCharacters(in: .whitespaces)
                            if mode == .teams {
                                store.addTeam(q)
                            } else {
                                store.addAthlete(name: q, team: nil)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.accent)
                                Text("Add \"\(searchText.trimmingCharacters(in: .whitespaces))\"")
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Spacer()
                                AppBadge(text: mode == .teams ? "TEAM" : "ATHLETE")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Add \(mode == .teams ? "Team" : "Athlete")")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
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
    @State private var expanded             = true
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
                HStack(spacing: Spacing.md - 2) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(event.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(dateLabel).font(.caption).foregroundStyle(.textTertiary)
                            Text("·").foregroundStyle(.textQuaternary)
                            Text(event.city).font(.caption).foregroundStyle(.textTertiary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        AppBadge(text: "\(registrations.count)")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.textTertiary)
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.name), \(registrations.count) registrations. \(expanded ? "Collapse" : "Expand")")

            if expanded {
                AppHairline()
                tournamentLinkBar
                AppHairline(color: .white.opacity(0.05))

                VStack(spacing: 0) {
                    ForEach(Array(registrations.enumerated()), id: \.offset) { i, reg in
                        let matchesForAthlete = scheduleMatches.filter {
                            ($0.athleteName?.lowercased() ?? "") == reg.athlete.name.lowercased()
                        }
                        TrackedAthleteRow(
                            athlete: reg.athlete,
                            division: reg.division,
                            scheduleMatches: matchesForAthlete
                        )
                        if i < registrations.count - 1 {
                            AppHairline(color: .white.opacity(0.05)).padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accent.opacity(0.2), lineWidth: 1)
        )
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
        HStack(spacing: Spacing.md - 2) {
            Image(systemName: "trophy.fill")
                .font(.caption2)
                .foregroundStyle(linkedTournamentId != nil ? .accent : .textQuaternary)

            if let name = linkedTournamentName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(tournaments.isEmpty ? "Loading tournaments…" : "Link bracket tournament")
                    .font(.caption)
                    .foregroundStyle(.textTertiary)
            }

            Spacer()

            if linkedTournamentId != nil {
                if isLoadingSchedule {
                    ProgressView().tint(.accent).scaleEffect(0.7)
                } else if scheduleMatches.isEmpty {
                    Button(action: onLoadSchedule) {
                        Text("Load Schedule")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.accent)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Color.accentWashLight)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onRefreshSchedule) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(.accent.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh schedule")
                }
                Button { showTournamentPicker = true } label: {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change linked tournament")
            } else {
                Button { showTournamentPicker = true } label: {
                    Text("Link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(tournaments.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.md - 2)
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

    @Environment(TrackingStore.self) private var store

    private var isTracked: Bool {
        store.trackedAthletes.contains { TrackingStore.nameMatch(tracked: $0.name, against: athlete.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.md) {
                Circle().fill(Color.beltColor(division.belt)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(athlete.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.textPrimary.opacity(0.9))
                    Text(athlete.team)
                        .font(.caption)
                        .foregroundStyle(.textTertiary)
                }
                Spacer()
                AppBadge(text: divisionShort, style: .ghost)

                if isTracked {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.accent.opacity(0.7))
                        .accessibilityLabel("Tracked")
                } else {
                    Button {
                        withAnimation {
                            store.addAthlete(name: athlete.name, team: athlete.team)
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Track \(athlete.name)")
                }
            }

            if scheduleMatches.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Color.white.opacity(0.15)).frame(width: 5, height: 5)
                    Text("No bracket assigned yet")
                        .font(.system(size: 10))
                        .foregroundStyle(.textTertiary)
                }
                .padding(.leading, 20)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(scheduleMatches) { match in ScheduleMatchRow(match: match) }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.md - 2)
    }

    private var divisionShort: String { "\(division.belt.capitalized) · \(division.weightClass)" }
}

// MARK: - Schedule match row

struct ScheduleMatchRow: View {
    let match: ScheduleMatch

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 4) {
                if let mat = match.mat, !mat.isEmpty {
                    Text(mat)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.accent)
                }
                if let fight = match.fight {
                    Text("Fight \(fight)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.textSecondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentWashFaint)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.accent.opacity(0.2), lineWidth: 1))

            if let when = match.when, !when.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.system(size: 9))
                    Text(when).font(.system(size: 10))
                }
                .foregroundStyle(.textTertiary)
            }

            if let opponent = match.opponent, !opponent.isEmpty {
                Text("vs \(opponent)")
                    .font(.system(size: 10))
                    .foregroundStyle(.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Text(roundLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
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
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accent)
                                .font(.caption)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .searchable(text: $search, prompt: "Search tournaments")
            .navigationTitle("Select Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
