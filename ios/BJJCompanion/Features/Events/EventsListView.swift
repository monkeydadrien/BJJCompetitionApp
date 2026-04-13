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
                    ProgressView("Loading events…")
                        .tint(.gold)
                } else if repo.events.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(repo.errorMessage ?? "Pull to refresh")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("IBJJF Events")
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
        VStack(alignment: .leading, spacing: 10) {

            Text(event.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack {
                Label(dateRange, systemImage: "calendar")
                Spacer()
                Label(event.city, systemImage: "mappin.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 8) {
                if let next = event.nextDeadline {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(pricingColor)
                            .frame(width: 7, height: 7)
                        Text("\(next.priceFormatted) · \(next.deadlineFormatted)")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(pricingColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pricingColor.opacity(0.15))
                    .clipShape(Capsule())
                }
                Spacer()
                if event.hasCombo {
                    Text("Gi + No-Gi")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.gold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.gold.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text("\(event.divisions.count) div")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if myDivisionCount > 0 {
                Label(
                    "\(myDivisionCount) athlete\(myDivisionCount == 1 ? "" : "s") in your division\(myDivisions.count > 1 ? "s" : "")",
                    systemImage: "person.2.fill"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.gold)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
