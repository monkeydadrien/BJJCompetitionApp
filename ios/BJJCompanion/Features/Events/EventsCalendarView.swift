import SwiftUI

// MARK: - Events calendar view
//
// Month-grid + day-agenda layout (Apple Calendar feel). Shares filter state
// with `EventsListContent` via a shared `@Binding<EventFilter>` and an
// `@AppStorage` distance key — toggling between list and calendar is just
// two windows on the same filtered set.

struct EventsCalendarView: View {

    // Pre-filtered by the parent `EventsListView`.
    let events:      [BJJEvent]
    let myDivisions: [MyDivision]
    let homeCity:    HomeCity?

    @Binding var filter: EventFilter
    @AppStorage("eventsDistanceFilter") private var distanceFilterRaw: Int = DistanceFilter.all.rawValue

    @Environment(HomeCityStore.self) private var homeCityStore

    @State private var visibleMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay:  Date = Calendar.current.startOfDay(for: Date())

    private var distanceFilter: DistanceFilter {
        DistanceFilter(rawValue: distanceFilterRaw) ?? .all
    }

    /// For every day in each event's [start, end] span, bucket the event under
    /// that day (so Brasileiro's five days each get the event). Cheap at ~126
    /// events × ≤5 days.
    private var eventsByDay: [Date: [BJJEvent]] {
        var bucket: [Date: [BJJEvent]] = [:]
        let cal = Calendar.current
        for ev in events {
            guard let s = ev.startDateParsed, let e = ev.endDateParsed else { continue }
            var d = cal.startOfDay(for: s)
            let end = cal.startOfDay(for: e)
            while d <= end {
                bucket[d, default: []].append(ev)
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        return bucket
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {

                // ── Shared filter controls (state lives on EventsListView) ──
                Picker("Filter", selection: $filter) {
                    ForEach(EventFilter.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

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

                // ── Month header with chevrons + optional "Today" pill ──
                MonthHeader(
                    visibleMonth: $visibleMonth,
                    selectedDay:  $selectedDay
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

                WeekdayStrip()
                    .padding(.horizontal, Spacing.lg)

                MonthGrid(
                    visibleMonth: visibleMonth,
                    selectedDay:  $selectedDay,
                    eventsByDay:  eventsByDay
                )
                .padding(.horizontal, Spacing.lg)

                AppHairline()
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)

                dayAgenda
                    .padding(.horizontal, Spacing.lg)
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - Day agenda

    private var dayAgenda: some View {
        let dayEvents = eventsByDay[selectedDay] ?? []
        return VStack(alignment: .leading, spacing: Spacing.md) {
            AppSectionLabel("\(Self.agendaHeaderFormatter.string(from: selectedDay))  ·  \(dayEvents.count) event\(dayEvents.count == 1 ? "" : "s")")

            if dayEvents.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.textQuaternary)
                    Text("No events on this day")
                        .font(.subheadline)
                        .foregroundStyle(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(dayEvents) { ev in
                        NavigationLink(destination: EventDetailView(event: ev)) {
                            EventRowView(event: ev, myDivisions: myDivisions, homeCity: homeCity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private static let agendaHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Month header

private struct MonthHeader: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDay:  Date

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var isViewingCurrentMonth: Bool {
        Calendar.current.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            chevronButton(systemImage: "chevron.left", accessibility: "Previous month") {
                step(-1)
            }

            Text(Self.monthFormatter.string(from: visibleMonth))
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .frame(maxWidth: .infinity)

            if !isViewingCurrentMonth {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let today = Date()
                        visibleMonth = Calendar.current.startOfMonth(for: today)
                        selectedDay  = Calendar.current.startOfDay(for: today)
                    }
                } label: {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.accent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.accentWashLight)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jump to today")
            }

            chevronButton(systemImage: "chevron.right", accessibility: "Next month") {
                step(1)
            }
        }
    }

    private func chevronButton(systemImage: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.accent)
                .frame(width: 32, height: 32)
                .background(Color.accentWashFaint)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private func step(_ months: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = cal.startOfMonth(for: next)
        }
    }
}

// MARK: - Weekday strip

private struct WeekdayStrip: View {
    // Sunday-first to match `Calendar.current.firstWeekday == 1` for en_US.
    // `shortWeekdaySymbols` returns ["Sun","Mon",...]; take first letter.
    private static let labels: [String] = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.veryShortWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
    }()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.labels, id: \.self) { label in
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    let visibleMonth: Date
    @Binding var selectedDay: Date
    let eventsByDay: [Date: [BJJEvent]]

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    /// 42 days: step back to the first Sunday on/before the 1st of the month,
    /// then 6 weeks of 7 = 42 cells. Covers any month layout.
    private var gridDays: [Date] {
        let cal = Calendar.current
        let firstOfMonth = cal.startOfMonth(for: visibleMonth)
        let weekday = cal.component(.weekday, from: firstOfMonth) // 1 = Sun
        let offset = weekday - cal.firstWeekday
        let start = cal.date(byAdding: .day, value: -offset, to: firstOfMonth) ?? firstOfMonth
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridDays, id: \.self) { day in
                DayCell(
                    day:              day,
                    isInVisibleMonth: Calendar.current.isDate(day, equalTo: visibleMonth, toGranularity: .month),
                    isToday:          Calendar.current.isDateInToday(day),
                    isSelected:       Calendar.current.isDate(day, inSameDayAs: selectedDay),
                    eventCount:       eventsByDay[day]?.count ?? 0
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedDay = day
                    }
                }
            }
        }
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let isInVisibleMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let eventCount: Int

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 28, height: 28)
                }
                Text(dayNumber)
                    .font(.subheadline.weight(isToday ? .bold : .medium))
                    .foregroundStyle(numberColor)
            }
            .frame(height: 28)

            // Event dots / overflow count
            Group {
                if eventCount == 0 {
                    Circle().fill(Color.clear).frame(width: 4, height: 4)
                } else if eventCount <= 3 {
                    HStack(spacing: 2) {
                        ForEach(0..<eventCount, id: \.self) { _ in
                            Circle()
                                .fill(Color.accent)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Text("+\(eventCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.accent)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accent : Color.clear, lineWidth: 1)
        )
        .opacity(isInVisibleMonth ? 1.0 : 0.35)
    }

    private var numberColor: Color {
        if isToday { return .black }
        return .textPrimary
    }
}

// MARK: - Calendar convenience

extension Calendar {
    fileprivate func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
