import SwiftUI
import UIKit

enum HAAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum HATheme {
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.72)

    static let card = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.14, alpha: 1)
            : UIColor.secondarySystemGroupedBackground
    })

    static let cardStroke = Color.primary.opacity(0.08)
    static let secondaryText = Color.secondary
    static let screen = Color(uiColor: .systemBackground)
}
