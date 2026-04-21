import SwiftUI

enum EventFilter: String, CaseIterable {
    case adults = "Adults"
    case kids   = "Kids"
    case all    = "All"
}

/// Maximum distance from home city. `rawValue` is miles, `0` = no filter.
enum DistanceFilter: Int, CaseIterable, Identifiable {
    case all  = 0
    case m50  = 50
    case m100 = 100
    case m250 = 250
    case m500 = 500

    var id: Int { rawValue }
    var label: String { self == .all ? "All" : "\(rawValue) mi" }
}

struct EventsListView: View {

    @Environment(EventsRepository.self) private var repo
    @Environment(DivisionsStore.self)   private var divisions
    @Environment(HomeCityStore.self)    private var homeCityStore
    @State private var filter: EventFilter = .adults
    @AppStorage("eventsDistanceFilter") private var distanceFilterRaw: Int = DistanceFilter.all.rawValue

    private var distanceFilter: DistanceFilter {
        DistanceFilter(rawValue: distanceFilterRaw) ?? .all
    }

    var body: some View {
        NavigationStack {
            Group {
                if repo.isLoading && repo.events.isEmpty {
                    ZStack {
                        Color.appBackground.ignoresSafeArea()
                        ProgressView("Loading events…").tint(.accent)
                    }
                } else if repo.events.isEmpty {
                    ZStack {
                        Color.appBackground.ignoresSafeArea()
                        ContentUnavailableView(
                            "No Events",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text(repo.errorMessage ?? "Pull to refresh")
                        )
                    }
                } else {
                    list
                }
            }
            .navigationTitle("IBJJF Events")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if repo.isLoading {
                        ProgressView().tint(.accent)
                    } else {
                        Button { Task { await repo.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.accent)
                        }
                        .accessibilityLabel("Refresh events")
                    }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            // Age-group filter
            Picker("Filter", selection: $filter) {
                ForEach(EventFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)

            // Distance filter (no-op until a home city is set in Settings)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Picker("Distance", selection: $distanceFilterRaw) {
                    ForEach(DistanceFilter.allCases) { df in
                        Text(df.label).tag(df.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if homeCityStore.city == nil && distanceFilter != .all {
                    Text("Set a home city in Settings to filter by distance.")
                        .font(.caption2)
                        .foregroundStyle(.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)

            LazyVStack(spacing: Spacing.md) {
                ForEach(filteredEvents) { event in
                    NavigationLink(destination: EventDetailView(event: event)) {
                        EventRowView(
                            event: event,
                            myDivisions: divisions.myDivisions,
                            homeCity: homeCityStore.city
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .refreshable { await repo.refresh() }
    }

    private var filteredEvents: [BJJEvent] {
        let now = Date()
        var upcoming = repo.events
            .filter { ($0.endDateParsed ?? .distantPast) >= now }
            .sorted { ($0.startDateParsed ?? .distantFuture) < ($1.startDateParsed ?? .distantFuture) }
        switch filter {
        case .all:    break
        case .adults: upcoming = upcoming.filter { $0.hasAdultDivisions }
        case .kids:   upcoming = upcoming.filter { $0.hasKidsDivisions }
        }

        if distanceFilter != .all, let home = homeCityStore.city {
            let limit = Double(distanceFilter.rawValue)
            upcoming = upcoming.filter { ev in
                guard let d = ev.milesFrom(home) else { return false }
                return d <= limit
            }
        }
        return upcoming
    }
}

// MARK: - Event card
//
// Hierarchy lessons applied (Erik Kennedy / Refactoring UI):
//  - One dominant element: the event name (.headline, primary text).
//  - Supporting metadata uses tertiary text + caption — clearly subordinate.
//  - Pricing pill is the second visual focal point: tinted by tier urgency.
//  - "GI + NO-GI" and division/athlete counts are de-emphasized so the card
//    has a clear reading order: name → date/place → price → my-division.

struct EventRowView: View {

    let event: BJJEvent
    let myDivisions: [MyDivision]
    var homeCity: HomeCity? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {

            // Title — the dominant element on the card.
            Text(event.name)
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Date + place + (optional) distance — all on one muted row.
            HStack(spacing: Spacing.sm) {
                Label(dateRange, systemImage: "calendar")
                    .labelStyle(.compactIcon)
                Spacer(minLength: Spacing.sm)
                Label(event.city, systemImage: "mappin.circle.fill")
                    .labelStyle(.compactIcon)
                if let miles = event.milesFrom(homeCity) {
                    Text("· \(Int(miles.rounded())) mi")
                        .foregroundStyle(.accent.opacity(0.75))
                        .fontWeight(.medium)
                }
            }
            .font(.caption)
            .foregroundStyle(.textTertiary)

            // Bottom row: pricing pill (focal) + flags + counts (subdued).
            HStack(alignment: .center, spacing: Spacing.sm) {
                if let next = event.nextDeadline {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(pricingColor)
                            .frame(width: 6, height: 6)
                        Text("\(next.priceFormatted) · \(next.deadlineFormatted)")
                            .foregroundStyle(pricingColor)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(pricingColor.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(pricingColor.opacity(0.25), lineWidth: 1))
                }
                Spacer()
                if event.hasCombo {
                    Text("GI + NO-GI")
                        .font(.appBadge)
                        .foregroundStyle(.textTertiary)
                        .kerning(0.6)
                        .padding(.horizontal, Spacing.sm - 2)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(event.divisions.count) divisions")
                    Text("\(event.divisions.flatMap { $0.athletes }.count) athletes")
                }
                .font(.caption2)
                .foregroundStyle(.textQuaternary)
            }

            // "X in your divisions" callout when applicable.
            if myDivisionCount > 0 {
                HStack(spacing: 5) {
                    Circle().fill(Color.accent).frame(width: 5, height: 5)
                    Text("\(myDivisionCount) athlete\(myDivisionCount == 1 ? "" : "s") in your division\(myDivisions.count > 1 ? "s" : "")")
                        .foregroundStyle(.accent)
                }
                .font(.caption)
                .fontWeight(.medium)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.cardBorder, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            // Pricing-tier urgency rail (3pt color stripe down the left edge).
            RoundedRectangle(cornerRadius: 2)
                .fill(pricingColor)
                .frame(width: 3)
                .padding(.vertical, Spacing.lg)
        }
    }

    private var dateRange: String {
        guard let s = event.startDateParsed else { return event.startDate }
        let f = DateFormatter.display
        if event.startDate == event.endDate { return f.string(from: s) }
        guard let e = event.endDateParsed else { return f.string(from: s) }
        return "\(f.string(from: s)) – \(f.string(from: e))"
    }

    /// Color reflecting where the current deadline sits in the tier list.
    private var pricingColor: Color {
        guard let next = event.nextDeadline,
              let idx = event.priceTiers.firstIndex(where: { $0.deadline == next.deadline })
        else { return .secondary }
        let count = event.priceTiers.count
        if idx == 0              { return .pricingEarly }
        if idx == count - 1      { return .pricingLate }
        return .pricingMid
    }

    private var myDivisionCount: Int {
        myDivisions.flatMap { div in
            event.divisions.filter { $0.matches(div) }.flatMap { $0.athletes }
        }.count
    }
}

// MARK: - Compact icon label style
//
// Default `Label` puts a wide gap between the icon and the title. The
// compact style halves it and matches the icon to the title color so the
// pair reads as a single unit on a dense card.
private struct CompactIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

private extension LabelStyle where Self == CompactIconLabelStyle {
    static var compactIcon: CompactIconLabelStyle { CompactIconLabelStyle() }
}
