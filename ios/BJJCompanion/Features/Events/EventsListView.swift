import SwiftUI

struct EventsListView: View {

    @Environment(EventsRepository.self) private var repo
    @Environment(DivisionsStore.self)   private var divisions

    var body: some View {
        NavigationStack {
            Group {
                if repo.isLoading && repo.events.isEmpty {
                    ProgressView("Loading events…")
                } else if repo.events.isEmpty {
                    ContentUnavailableView("No Events", systemImage: "calendar.badge.exclamationmark",
                                          description: Text(repo.errorMessage ?? "Pull to refresh"))
                } else {
                    list
                }
            }
            .navigationTitle("IBJJF Events")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if repo.isLoading {
                        ProgressView()
                    } else {
                        Button { Task { await repo.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable { await repo.refresh() }
        }
    }

    private var list: some View {
        List(upcomingEvents) { event in
            NavigationLink(destination: EventDetailView(event: event)) {
                EventRowView(event: event, myDivisions: divisions.myDivisions)
            }
        }
    }

    private var upcomingEvents: [BJJEvent] {
        let now = Date()
        return repo.events
            .filter { ($0.endDateParsed ?? .distantPast) >= now }
            .sorted { ($0.startDateParsed ?? .distantFuture) < ($1.startDateParsed ?? .distantFuture) }
    }
}

// MARK: - Row

struct EventRowView: View {

    let event: BJJEvent
    let myDivisions: [MyDivision]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.name)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Label(dateRange, systemImage: "calendar")
                Spacer()
                Label(event.city, systemImage: "mappin")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let next = event.nextDeadline {
                HStack {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("\(next.priceFormatted) until \(next.deadlineFormatted)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !myDivisions.isEmpty {
                let count = myDivisionCount
                if count > 0 {
                    Label("\(count) athlete\(count == 1 ? "" : "s") in your division\(myDivisions.count > 1 ? "s" : "")",
                          systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dateRange: String {
        guard let s = event.startDateParsed else { return event.startDate }
        let f = DateFormatter.display
        if event.startDate == event.endDate { return f.string(from: s) }
        guard let e = event.endDateParsed else { return f.string(from: s) }
        return "\(f.string(from: s)) – \(f.string(from: e))"
    }

    private var myDivisionCount: Int {
        myDivisions.flatMap { div in
            event.divisions.filter { $0.matches(div) }.flatMap { $0.athletes }
        }.count
    }
}
