import SwiftUI

extension Color {
    /// Metallic gold used throughout the app for accents, badges, and highlights.
    static let gold = Color(red: 0.831, green: 0.686, blue: 0.216)
}

/// Allows `.gold` in ShapeStyle contexts: `.foregroundStyle(.gold)`, `.tint(.gold)`, etc.
extension ShapeStyle where Self == Color {
    static var gold: Color { .gold }
}

extension Color {

    static func beltColor(_ belt: String) -> Color {
        switch belt.lowercased() {
        case "white":  return .white
        case "blue":   return Color(red: 0.20, green: 0.45, blue: 0.85)
        case "purple": return Color(red: 0.55, green: 0.10, blue: 0.75)
        case "brown":  return Color(red: 0.55, green: 0.27, blue: 0.07)
        case "black":  return .gold   // gold dot on dark bg = visible & fitting
        default:       return .secondary
        }
    }
}
