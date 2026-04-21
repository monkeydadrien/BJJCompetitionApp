import SwiftUI
import UIKit

struct EventDetailView: View {

    let event: BJJEvent
    @Environment(DivisionsStore.self) private var divisions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heroCard
                if !event.priceTiers.isEmpty { pricingSection }
                if !divisions.myDivisions.isEmpty { myDivisionsSection }
                allDivisionsSection
            }
            .padding(Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationBar()
    }

    // MARK: - Hero

    private var heroCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {

                Text(event.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Label(dateRange, systemImage: "calendar")
                    Spacer()
                    Label(event.city, systemImage: "mappin.circle.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.textTertiary)

                // Stats
                HStack(spacing: 0) {
                    StatBlock(value: "\(event.divisions.count)", label: "Divisions")
                    statDivider
                    StatBlock(value: "\(totalAthletes)", label: "Athletes")
                    if event.hasCombo {
                        statDivider
                        VStack(spacing: 3) {
                            Text("GI + NO-GI")
                                .font(.appBadge)
                                .foregroundStyle(.textPrimary.opacity(0.9))
                                .kerning(0.8)
                            Text("Available")
                                .font(.system(size: 10))
                                .foregroundStyle(.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if let venue = event.venue, !venue.isEmpty {
                    AppHairline()

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(venue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.textPrimary.opacity(0.85))

                        if let address = event.address, !address.isEmpty {
                            Button {
                                let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let url = URL(string: "maps://?q=\(q)") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(.accent)
                                        .font(.subheadline)
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.textSecondary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                        .foregroundStyle(.textQuaternary)
                                }
                                .padding(Spacing.md - 2)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.cardBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open address in Maps")
                        }
                    }
                }

                // Primary CTA — opens IBJJF event page where the real "Register Now" lives.
                Button {
                    if let url = URL(string: "https://ibjjf.com/events/\(event.slug)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "square.and.pencil")
                        Text("Register Now")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                // Secondary — opens the athlete/division registrations page.
                Button {
                    if let url = URL(string: event.registrationUrl) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "person.2.fill")
                        Text("View Registered Athletes")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accentWashLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 30)
            .overlay(Color.white.opacity(0.10))
            .padding(.horizontal, 14)
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        let giTiers    = event.priceTiers.filter { !$0.name.contains("Combo") }
        let comboTiers = event.priceTiers.filter {  $0.name.contains("Combo") }
        let now        = Date()
        let nextGi     = giTiers.first    { ($0.deadlineParsed ?? .distantPast) > now }
        let nextCombo  = comboTiers.first { ($0.deadlineParsed ?? .distantPast) > now }

        return VStack(alignment: .leading, spacing: Spacing.md - 2) {
            AppSectionLabel("Registration")
            if comboTiers.isEmpty {
                PricingCard(title: nil, tiers: giTiers, nextDeadline: nextGi)
            } else {
                HStack(alignment: .top, spacing: Spacing.md - 2) {
                    PricingCard(title: "Gi", tiers: giTiers, nextDeadline: nextGi)
                    PricingCard(title: "Gi + No-Gi", tiers: comboTiers, nextDeadline: nextCombo)
                }
            }
        }
    }

    // MARK: - My Divisions

    private var myDivisionsSection: some View {
        let myDivs = myMatchingDivisions
        return VStack(alignment: .leading, spacing: Spacing.md - 2) {
            AppSectionLabel("My Division\(myDivs.count == 1 ? "" : "s")")
            AppCard(borderColor: myDivs.isEmpty ? .cardBorder : .accent.opacity(0.45)) {
                if myDivs.isEmpty {
                    HStack(spacing: Spacing.md - 2) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.textQuaternary)
                            .font(.title3)
                        Text("No athletes registered in your divisions yet")
                            .font(.subheadline)
                            .foregroundStyle(.textTertiary)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(myDivs.enumerated()), id: \.element.id) { i, div in
                            DivisionSection(division: div)
                            if i < myDivs.count - 1 {
                                AppHairline().padding(.vertical, Spacing.xs)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - All Divisions

    private var allDivisionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md - 2) {
            AppSectionLabel("All Divisions · \(event.divisions.count)")
            AppCard {
                VStack(spacing: 0) {
                    ForEach(Array(divisionsByBelt.enumerated()), id: \.element.belt) { i, group in
                        BeltGroup(belt: group.belt, divisions: group.divisions)
                        if i < divisionsByBelt.count - 1 {
                            AppHairline().padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var totalAthletes: Int { event.divisions.reduce(0) { $0 + $1.athletes.count } }

    // Top-to-bottom belt order for adult ranks (case-insensitive match).
    private static let beltOrder = ["BLACK", "BROWN", "PURPLE", "BLUE", "WHITE"]

    private var divisionsByBelt: [(belt: String, divisions: [Division])] {
        var grouped: [String: [Division]] = [:]
        for div in event.divisions { grouped[div.belt.uppercased(), default: []].append(div) }
        let known = Self.beltOrder.compactMap { belt -> (String, [Division])? in
            guard let divs = grouped[belt], !divs.isEmpty else { return nil }
            return (belt, divs)
        }
        let knownBelts = Set(Self.beltOrder)
        let extra = grouped.filter { !knownBelts.contains($0.key) }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
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
        event.divisions.filter { div in divisions.myDivisions.contains { div.matches($0) } }
    }
}

// MARK: - Stat block

struct StatBlock: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.appStat)
                .foregroundStyle(.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.textTertiary)
                .kerning(0.3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pricing card

struct PricingCard: View {
    let title: String?
    let tiers: [PriceTier]
    let nextDeadline: PriceTier?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.textTertiary)
                    .kerning(1.2)
            }
            ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                if index > 0 {
                    AppHairline()
                }
                PriceTierRow(
                    tier: tier, index: index,
                    count: tiers.count,
                    isNext: tier.deadline == nextDeadline?.deadline
                )
            }
        }
        .appCardStyle(padding: 14)
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
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(tierColor)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tierLabel)
                        .font(.subheadline)
                        .fontWeight(isNext ? .semibold : .regular)
                        .foregroundStyle(isNext ? tierColor : .textPrimary.opacity(0.85))
                    Text("Until \(tier.deadlineFormatted)")
                        .font(.caption)
                        .foregroundStyle(isNext ? tierColor.opacity(0.75) : .textTertiary)
                }
            }
            Spacer()
            Text(tier.priceFormatted)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(isNext ? tierColor : .textPrimary.opacity(0.85))
        }
        .padding(isNext ? Spacing.sm : 0)
        .background(isNext ? tierColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tierLabel: String {
        if count == 1         { return "Standard" }
        if index == 0         { return "Early Bird" }
        if index == count - 1 { return "Late Registration" }
        return "Standard"
    }

    private var tierColor: Color {
        if index == 0         { return .pricingEarly }
        if index == count - 1 { return .pricingLate }
        return .pricingMid
    }
}

// MARK: - Belt group

struct BeltGroup: View {
    let belt: String
    let divisions: [Division]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 0) {
                ForEach(Array(divisions.enumerated()), id: \.element.id) { i, div in
                    DivisionSection(division: div)
                        .padding(.top, i == 0 ? Spacing.sm : 0)
                    if i < divisions.count - 1 {
                        AppHairline(color: .white.opacity(0.06)).padding(.vertical, 2)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.md - 2) {
                Circle()
                    .fill(Color.beltColor(belt))
                    .frame(width: 9, height: 9)
                Text(belt.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary.opacity(0.85))
                Spacer()
                AppBadge(text: "\(divisions.count)", style: .ghost)
            }
        }
        .tint(.textTertiary)
    }
}

// MARK: - Division row

struct DivisionSection: View {
    let division: Division
    @State private var expanded = false
    @Environment(TrackingStore.self) private var trackingStore

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 0) {
                ForEach(Array(division.athletes.enumerated()), id: \.element.id) { i, athlete in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(athlete.name)
                                .font(.subheadline)
                                .foregroundStyle(.textPrimary.opacity(0.8))
                            Text(athlete.team)
                                .font(.caption)
                                .foregroundStyle(.textTertiary)
                        }
                        Spacer()
                        // Tracking indicator
                        if trackingStore.isTrackingAthlete(name: athlete.name) ||
                           trackingStore.matchesAnyTracked(name: athlete.name, team: athlete.team) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.accent.opacity(0.7))
                                .accessibilityLabel("Tracked")
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.leading, 4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if !trackingStore.isTrackingAthlete(name: athlete.name) {
                            Button {
                                trackingStore.addAthlete(name: athlete.name, team: athlete.team)
                            } label: {
                                Label("Track \(athlete.name)", systemImage: "person.fill.badge.plus")
                            }
                        } else {
                            Button(role: .destructive) {
                                if let idx = trackingStore.trackedAthletes.firstIndex(where: {
                                    $0.name.lowercased() == athlete.name.lowercased()
                                }) {
                                    trackingStore.trackedAthletes.remove(at: idx)
                                }
                            } label: {
                                Label("Untrack \(athlete.name)", systemImage: "person.fill.xmark")
                            }
                        }
                        if !trackingStore.isTrackingTeam(athlete.team) {
                            Button {
                                trackingStore.addTeam(athlete.team)
                            } label: {
                                Label("Track \(athlete.team)", systemImage: "person.3.fill")
                            }
                        } else {
                            Button(role: .destructive) {
                                if let idx = trackingStore.trackedTeams.firstIndex(where: {
                                    $0.name.lowercased() == athlete.team.lowercased()
                                }) {
                                    trackingStore.trackedTeams.remove(at: idx)
                                }
                            } label: {
                                Label("Untrack \(athlete.team)", systemImage: "person.3.sequence.fill")
                            }
                        }
                    }
                    if i < division.athletes.count - 1 {
                        AppHairline(color: .white.opacity(0.06))
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(division.id.split(separator: "/").dropFirst().joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                Spacer()
                AppBadge(text: "\(division.count)", style: .ghost)
            }
        }
        .tint(.textQuaternary)
    }
}
