import SwiftUI
import UIKit

struct EventDetailView: View {

    let event: BJJEvent
    @Environment(DivisionsStore.self) private var divisions

    var body: some View {
        List {
            // Dates & location
            Section("Details") {
                LabeledContent("Date", value: dateRange)
                if let venue = event.venue, !venue.isEmpty {
                    LabeledContent("Venue", value: venue)
                }
                if let address = event.address, !address.isEmpty {
                    Label(address, systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "maps://?q=\(query)") {
                                UIApplication.shared.open(url)
                            }
                        }
                } else {
                    LabeledContent("Location", value: "\(event.city), \(event.country)")
                }
                Link("Register / Athletes List",
                     destination: URL(string: event.registrationUrl)!)
            }

            // Price tiers
            let giTiers    = event.priceTiers.filter { !$0.name.contains("Combo") }
            let comboTiers = event.priceTiers.filter {  $0.name.contains("Combo") }
            let now        = Date()
            let nextGi     = giTiers.first    { ($0.deadlineParsed ?? .distantPast) > now }
            let nextCombo  = comboTiers.first { ($0.deadlineParsed ?? .distantPast) > now }

            if !giTiers.isEmpty {
                Section(comboTiers.isEmpty ? "Registration Fees" : "Gi") {
                    ForEach(Array(giTiers.enumerated()), id: \.offset) { index, tier in
                        PriceTierRow(
                            tier: tier,
                            index: index,
                            count: giTiers.count,
                            isNext: tier.deadline == nextGi?.deadline
                        )
                    }
                }
            }
            if !comboTiers.isEmpty {
                Section("Gi + No-Gi") {
                    ForEach(Array(comboTiers.enumerated()), id: \.offset) { index, tier in
                        PriceTierRow(
                            tier: tier,
                            index: index,
                            count: comboTiers.count,
                            isNext: tier.deadline == nextCombo?.deadline
                        )
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

            // All divisions grouped by belt (collapsed by default)
            Section("All Divisions (\(event.divisions.count))") {
                ForEach(divisionsByBelt, id: \.belt) { group in
                    BeltGroup(belt: group.belt, divisions: group.divisions)
                }
            }
        }
        .tint(.gold)
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let beltOrder = ["White", "Blue", "Purple", "Brown", "Black"]

    private var divisionsByBelt: [(belt: String, divisions: [Division])] {
        var grouped: [String: [Division]] = [:]
        for div in event.divisions {
            grouped[div.belt, default: []].append(div)
        }
        let known = Self.beltOrder.compactMap { belt -> (String, [Division])? in
            guard let divs = grouped[belt], !divs.isEmpty else { return nil }
            return (belt, divs)
        }
        let knownBelts = Set(Self.beltOrder)
        let extra = grouped
            .filter { !knownBelts.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        return (known + extra).map { (belt: $0.0, divisions: $0.1) }
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
    let index: Int
    let count: Int
    let isNext: Bool

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(tierColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tierLabel)
                        .font(.subheadline)
                        .fontWeight(isNext ? .semibold : .regular)
                        .foregroundStyle(isNext ? tierColor : .primary)
                    Text("Until \(tier.deadlineFormatted)")
                        .font(.caption)
                        .foregroundStyle(isNext ? tierColor.opacity(0.8) : .secondary)
                }
            }
            Spacer()
            Text(tier.priceFormatted)
                .font(.headline)
                .foregroundStyle(isNext ? tierColor : .primary)
        }
        .padding(.vertical, 2)
        .listRowBackground(isNext ? tierColor.opacity(0.08) : nil)
    }

    /// Human-readable label based on position in the tier list
    private var tierLabel: String {
        if count == 1 { return "Standard" }
        if index == 0 { return "Early Bird" }
        if index == count - 1 { return "Late Registration" }
        return "Standard"
    }

    /// Green → amber → red progression across tiers
    private var tierColor: Color {
        if index == 0              { return Color(red: 0.25, green: 0.75, blue: 0.35) } // green
        if index == count - 1      { return Color(red: 0.85, green: 0.25, blue: 0.20) } // red
        return Color(red: 0.90, green: 0.65, blue: 0.10)                                // amber
    }
}

// MARK: - Belt group

struct BeltGroup: View {

    let belt: String
    let divisions: [Division]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(divisions) { div in
                DivisionSection(division: div)
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.beltColor(belt))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                Text(belt.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(divisions.count)")
                    .font(.caption)
                    .foregroundStyle(.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gold.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
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
