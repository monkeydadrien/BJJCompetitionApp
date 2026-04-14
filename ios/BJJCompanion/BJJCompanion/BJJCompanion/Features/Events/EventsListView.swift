import SwiftUI

enum EventFilter: String, CaseIterable {
    case adults = "Adults"
    case kids   = "Kids"
    case all    = "All"
}

struct EventsListView: View {

    @Environment(EventsRepository.self) private var repo
    @Environment(DivisionsStore.self)   private var divisions
    @State private var filter: EventFilter = .adults

    var body: some View {
        NavigationStack {
            Group {
                if repo.isLoading && repo.events.isEmpty {
                    ZStack {
                        Color.appBackground.ignoresSafeArea()
                        ProgressView("Loading events…").tint(.gold)
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
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if repo.isLoading {
                        ProgressView().tint(.gold)
                    } else {
                        Button { Task { await repo.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.gold)
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            // Segmented filter
            Picker("Filter", selection: $filter) {
                ForEach(EventFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            LazyVStack(spacing: 10) {
                ForEach(filteredEvents) { event in
                    NavigationLink(destination: EventDetailView(event: event)) {
                        EventRowView(event: event, myDivisions: divisions.myDivisions)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .refreshable { await repo.refresh() }
    }

    private var filteredEvents: [BJJEvent] {
        let now = Date()
        let upcoming = repo.events
            .filter { ($0.endDateParsed ?? .distantPast) >= now }
            .sorted { ($0.startDateParsed ?? .distantFuture) < ($1.startDateParsed ?? .distantFuture) }
        switch filter {
        case .all:    return upcoming
        case .adults: return upcoming.filter { $0.hasAdultDivisions }
        case .kids:   return upcoming.filter { $0.hasKidsDivisions }
        }
    }
}

// MARK: - Event card

struct EventRowView: View {

    let event: BJJEvent
    let myDivisions: [MyDivision]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {

            Text(event.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack {
                Label(dateRange, systemImage: "calendar")
                Spacer()
                Label(event.city, systemImage: "mappin.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .center, spacing: 8) {
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pricingColor.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(pricingColor.opacity(0.25), lineWidth: 1))
                }
                Spacer()
                if event.hasCombo {
                    Text("GI + NO-GI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .kerning(0.6)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(event.divisions.count) divisions")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.25))
                    Text("\(event.divisions.flatMap { $0.athletes }.count) athletes")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.25))
                }
            }

            if myDivisionCount > 0 {
                HStack(spacing: 5) {
                    Circle().fill(Color.gold).frame(width: 5, height: 5)
                    Text("\(myDivisionCount) athlete\(myDivisionCount == 1 ? "" : "s") in your division\(myDivisions.count > 1 ? "s" : "")")
                        .foregroundStyle(.gold)
                }
                .font(.caption)
                .fontWeight(.medium)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(pricingColor)
                .frame(width: 3)
                .padding(.vertical, 16)
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
        if idx == 0              { return Color(red: 0.25, green: 0.75, blue: 0.35) } // green  – early
        if idx == count - 1      { return Color(red: 0.85, green: 0.25, blue: 0.20) } // red    – late
        return Color(red: 0.90, green: 0.65, blue: 0.10)                               // amber  – standard
    }

    private var myDivisionCount: Int {
        myDivisions.flatMap { div in
            event.divisions.filter { $0.matches(div) }.flatMap { $0.athletes }
        }.count
    }
}
