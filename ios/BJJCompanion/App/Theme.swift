import SwiftUI

// MARK: - Color tokens
//
// Semantic, named tokens replace ad-hoc `.white.opacity(0.35)` and
// `.opacity(0.07)` sprinkles scattered across the app. New code should use
// these names. The legacy aliases at the bottom of the Color extension keep
// existing call sites working without a sweeping rename.
//
// Ramp follows Refactoring UI's 9-shade approach: 50 = lightest tint, 900 =
// most saturated/dark. We derive the ramp from the canonical accent
// (#3A8EFF) by mixing toward white (lighter) or toward black (darker) and
// also keep two transparency-based "wash" tones for tinted backgrounds.

extension Color {

    // MARK: Surfaces

    /// Base app background — #080C10
    static let appBackground  = Color(red: 0.031, green: 0.047, blue: 0.063)
    /// Card surface — #111820
    static let cardSurface    = Color(red: 0.067, green: 0.094, blue: 0.125)
    /// Elevated surface (one step up from card) — #1A2535
    static let cardElevated   = Color(red: 0.102, green: 0.145, blue: 0.208)
    /// Faint border that separates surfaces without hard contrast.
    static let cardBorder     = Color.white.opacity(0.07)
    /// Faint hairline divider (rows inside a card).
    static let cardDivider    = Color.white.opacity(0.06)

    // MARK: Text — use these instead of `.white.opacity(N)`

    /// Headlines, primary values — full white.
    static let textPrimary    = Color.white
    /// Body text — slightly muted to reduce visual weight on dark surfaces.
    static let textSecondary  = Color.white.opacity(0.65)
    /// Captions, supporting metadata.
    static let textTertiary   = Color.white.opacity(0.40)
    /// Decorative or barely-visible labels (placeholders, faint hints).
    static let textQuaternary = Color.white.opacity(0.22)

    // MARK: Accent ramp — derived from #3A8EFF

    /// Lightest accent tint, used for hover-like feedback / very faint fills.
    static let accent50   = Color(red: 0.86, green: 0.92, blue: 1.00)
    static let accent100  = Color(red: 0.74, green: 0.85, blue: 1.00)
    static let accent200  = Color(red: 0.58, green: 0.74, blue: 1.00)
    static let accent300  = Color(red: 0.43, green: 0.65, blue: 1.00)
    /// Canonical accent — #3A8EFF.
    static let accent     = Color(red: 0.227, green: 0.557, blue: 1.0)
    static let accent600  = Color(red: 0.18, green: 0.46, blue: 0.85)
    static let accent700  = Color(red: 0.13, green: 0.36, blue: 0.70)
    static let accent800  = Color(red: 0.09, green: 0.27, blue: 0.55)
    static let accent900  = Color(red: 0.06, green: 0.18, blue: 0.40)

    /// Translucent accent washes (use `accent` over a surface for tinted fills).
    /// These map to the most common opacity values used pre-refactor.
    static let accentWashFaint  = Color.accent.opacity(0.08)
    static let accentWashLight  = Color.accent.opacity(0.12)
    static let accentWashStrong = Color.accent.opacity(0.20)
    /// Stroke for accent-tinted capsules / pills.
    static let accentBorder     = Color.accent.opacity(0.30)

    // MARK: Pricing-tier status colors

    static let pricingEarly = Color(red: 0.25, green: 0.75, blue: 0.35)  // green
    static let pricingMid   = Color(red: 0.90, green: 0.65, blue: 0.10)  // amber
    static let pricingLate  = Color(red: 0.85, green: 0.25, blue: 0.20)  // red

    // MARK: Belt colors

    static func beltColor(_ belt: String) -> Color {
        switch belt.lowercased() {
        case "white":  return .white
        case "blue":   return Color(red: 0.20, green: 0.45, blue: 0.85)
        case "purple": return Color(red: 0.55, green: 0.10, blue: 0.75)
        case "brown":  return Color(red: 0.55, green: 0.27, blue: 0.07)
        case "black":  return Color(white: 0.22)
        default:       return Color.white.opacity(0.4)
        }
    }

    // MARK: Legacy aliases — keep existing call sites compiling.
    //
    // The accent color was originally named `.gold` even though it is
    // electric blue. Renaming in one pass is high-risk; instead we keep
    // `.gold` as an alias for `.accent` and migrate file-by-file.

    static var gold: Color { accent }
}

/// Allows `.accent` / `.gold` / surface tokens in ShapeStyle contexts:
/// `.foregroundStyle(.accent)`, `.tint(.gold)`, `.background(.cardSurface)`.
extension ShapeStyle where Self == Color {
    static var accent: Color         { .accent }
    static var gold: Color           { .gold }
    static var appBackground: Color  { .appBackground }
    static var cardSurface: Color    { .cardSurface }
    static var cardElevated: Color   { .cardElevated }
    static var cardBorder: Color     { .cardBorder }
    static var textPrimary: Color    { .textPrimary }
    static var textSecondary: Color  { .textSecondary }
    static var textTertiary: Color   { .textTertiary }
    static var textQuaternary: Color { .textQuaternary }
}

// MARK: - Spacing scale (4-pt grid)
//
// Used in place of magic-number paddings. Five steps cover ~95 % of the
// padding values previously used; reach for raw numbers only when needed.

enum Spacing {
    /// 4 — tight gap between adjacent inline elements
    static let xs: CGFloat = 4
    /// 8 — default gap inside a row
    static let sm: CGFloat = 8
    /// 12 — gap between rows or compact section padding
    static let md: CGFloat = 12
    /// 16 — standard card padding / screen edge inset
    static let lg: CGFloat = 16
    /// 24 — generous separation between major sections
    static let xl: CGFloat = 24
    /// 32 — bottom safe-area breathing room
    static let xxl: CGFloat = 32
}

// MARK: - Typography
//
// All sizes go through SF text styles so Dynamic Type works automatically.
// The two custom sizes (`.appStat`, `.appSectionLabel`) intentionally use
// `.system(size:)` because they're for purely visual elements (large
// stat numerals + uppercase tracking labels) where Dynamic Type would
// break the layout.

extension Font {
    /// Large rounded number for stat blocks ("12 Divisions").
    static let appStat = Font.system(size: 26, weight: .bold, design: .rounded)
    /// Uppercase, kerned section header ("REGISTRATION").
    static let appSectionLabel = Font.system(size: 11, weight: .semibold)
    /// Tiny uppercase badge text ("GI + NO-GI", "TEAM").
    static let appBadge = Font.system(size: 10, weight: .bold)
}

// MARK: - View modifiers
//
// Consolidates the repeated `.toolbarBackground(...)` / card-styling /
// badge-styling chains so each view file says what it means, not how it's
// painted.

/// Standard navigation bar styling.
///
/// iOS 26 renders the nav bar as a translucent Liquid Glass material by
/// default. The previous code forced `.toolbarBackground(Color.appBackground)`
/// which painted a flat solid bar on top of the glass — an iOS-15-era pattern
/// that hides the new material entirely. We now only set the color scheme
/// so titles/icons stay readable on the dark surface, and let the system
/// render the glass + scroll-edge fade itself.
struct AppNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    /// Apply consistent dark navigation-bar styling.
    func appNavigationBar() -> some View {
        modifier(AppNavigationBarModifier())
    }
}

/// Card surface: padded, rounded, hairline-bordered.
struct AppCardSurface: ViewModifier {
    var padding: CGFloat = Spacing.lg
    var cornerRadius: CGFloat = 14
    var borderColor: Color = .cardBorder

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    /// Apply card-surface styling (padding, surface color, hairline border).
    func appCardStyle(
        padding: CGFloat = Spacing.lg,
        cornerRadius: CGFloat = 14,
        borderColor: Color = .cardBorder
    ) -> some View {
        modifier(AppCardSurface(
            padding: padding,
            cornerRadius: cornerRadius,
            borderColor: borderColor
        ))
    }
}

// MARK: - Reusable atoms

/// Uppercase, kerned section header. Replaces inline `Text(...).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).kerning(...)`.
struct AppSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.appSectionLabel)
            .foregroundStyle(.textTertiary)
            .kerning(1.5)
            .padding(.horizontal, 2)
    }
}

/// Generic card container — equivalent to wrapping content in `.appCardStyle()`.
/// Kept as a free-standing struct because it improves call-site readability
/// (`AppCard { ... }`) and supports a custom border color for accent states.
struct AppCard<Content: View>: View {
    var borderColor: Color = .cardBorder
    var padding: CGFloat = Spacing.lg
    var cornerRadius: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .appCardStyle(
                padding: padding,
                cornerRadius: cornerRadius,
                borderColor: borderColor
            )
    }
}

/// Capsule badge — small text label with a tinted background and stroke.
/// Replaces the ~10 places that hand-roll a capsule with `.padding(.horizontal, 8).padding(.vertical, 3).background(...).clipShape(Capsule()).overlay(Capsule().strokeBorder(...))`.
struct AppBadge: View {
    let text: String
    var tint: Color = .accent
    var style: Style = .filled

    enum Style {
        case filled    // tinted background + stroke
        case ghost     // surface-only background, no stroke
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(style == .filled ? tint : .textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(style == .filled ? tint.opacity(0.12) : Color.white.opacity(0.07))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        style == .filled ? tint.opacity(0.25) : Color.clear,
                        lineWidth: 1
                    )
            )
    }
}

/// Hairline horizontal divider in card colors.
struct AppHairline: View {
    var color: Color = .cardDivider
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}
