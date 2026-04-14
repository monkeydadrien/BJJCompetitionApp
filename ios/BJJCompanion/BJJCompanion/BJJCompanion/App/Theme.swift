import SwiftUI

// MARK: - App colors

extension Color {
    /// Base app background — #080C10
    static let appBackground  = Color(red: 0.031, green: 0.047, blue: 0.063)
    /// Card surface — #111820
    static let cardSurface    = Color(red: 0.067, green: 0.094, blue: 0.125)
    /// Elevated surface — #1A2535
    static let cardElevated   = Color(red: 0.102, green: 0.145, blue: 0.208)
    /// Thin border — separates surfaces without hard contrast
    static let cardBorder     = Color.white.opacity(0.07)

    /// Electric blue accent — #3A8EFF
    static let gold = Color(red: 0.227, green: 0.557, blue: 1.0)

    static func beltColor(_ belt: String) -> Color {
        switch belt.lowercased() {
        case "white":  return .white
        case "blue":   return Color(red: 0.20, green: 0.45, blue: 0.85)
        case "purple": return Color(red: 0.55, green: 0.10, blue: 0.75)
        case "brown":  return Color(red: 0.55, green: 0.27, blue: 0.07)
        case "black":  return .gold
        default:       return Color.white.opacity(0.4)
        }
    }
}

/// Allows `.gold` in ShapeStyle contexts: `.foregroundStyle(.gold)`, `.tint(.gold)`, etc.
extension ShapeStyle where Self == Color {
    static var gold: Color { .gold }
    static var appBackground: Color { .appBackground }
    static var cardSurface: Color { .cardSurface }
}
