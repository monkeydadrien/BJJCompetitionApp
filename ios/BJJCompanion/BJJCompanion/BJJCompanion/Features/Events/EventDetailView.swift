import SwiftUI

struct EventDetailView: View {

    let event: BJJEvent
    @Environment(DivisionsStore.self) private var divisions

    var body: some View {
        List {
            // Dates & location
            Section("Details") {
                LabeledContent("Date", value: dateRange)
                LabeledContent("Location", value: "\(event.city), \(event.country)")
                Link("Register / Athletes List",
                     destination: URL(string: event.registrationUrl)!)
            }

            // Price tiers
            if !event.priceTiers.isEmpty {
                Section("Registration Fees") {
                    ForEach(Array(event.priceTiers.enumerated()), id: \.offset) { _, tier in
                        PriceTierRow(tier: tier)
                    }
                }
            }

            // My divisions
            if !divisions.myDivisions.isEmpty {
                let myDivs = myMatchingDivisions
                Section("My Division\(myDivs.count == 1 ? "" : "s")") {
                    if myDivs.isEmpty {
                        Text("No athletes registered in your divisions yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(myDivs) { div in
                            DivisionSection(division: div)
                        }
                    }
                }
            }

            // All divisions (collapsed by default)
            Section("All Divisions (\(event.divisions.count))") {
                ForEach(event.divisions) { div in
                    DivisionSection(division: div)
                }
            }
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dateRange: String {
        guard let s = event.startDateParsed else { return event.startDate }
        let f = DateFormatter.display
        if event.startDate == event.endDate { return f.string(from: s) }
        guard let e = event.endDateParsed else { return f.string(from: s) }
        return "\(f.string(from: s)) – \(f.string(from: e))"
    }

    private var myMatchingDivisions: [Division] {
        event.divisions.filter { div in
            divisions.myDivisions.contains { div.matches($0) }
        }
    }
}

// MARK: - Price tier row

struct PriceTierRow: View {

    let tier: PriceTier

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.name)
                    .font(.subheadline)
                Text("Until \(tier.deadlineFormatted)")
                    .font(.caption)
                    .foregroundStyle(isUpcoming ? .orange : .secondary)
            }
            Spacer()
            Text(tier.priceFormatted)
                .font(.headline)
                .foregroundStyle(isNext ? .orange : .primary)
        }
        .padding(.vertical, 2)
    }

    private var isUpcoming: Bool {
        (tier.deadlineParsed ?? .distantPast) > Date()
    }

    private var isNext: Bool {
        isUpcoming
    }
}

// MARK: - Division section

struct DivisionSection: View {

    let division: Division
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(division.athletes) { athlete in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(athlete.name)
                            .font(.subheadline)
                        Text(athlete.team)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        } label: {
            HStack {
                Text(division.id
                    .split(separator: "/")
                    .dropFirst()           // drop belt (shown in section header)
                    .joined(separator: " / "))
                    .font(.subheadline)
                Spacer()
                Text("\(division.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
    }
}
