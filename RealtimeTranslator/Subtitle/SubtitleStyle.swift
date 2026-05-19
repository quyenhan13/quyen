import SwiftUI

enum SubtitleStyle: String, CaseIterable {
    case classic = "Classic"
    case neon = "Neon"
    case brutalist = "Industrial Brutalist"
    
    var font: Font {
        switch self {
        case .classic:
            return .system(size: 26, weight: .bold, design: .rounded)
        case .neon:
            return .system(size: 28, weight: .black, design: .monospaced)
        case .brutalist:
            return .system(size: 24, weight: .heavy, design: .default)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .classic: return .white
        case .neon: return Color(red: 0.0, green: 1.0, blue: 0.8)
        case .brutalist: return .black
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .classic: return .black.opacity(0.7)
        case .neon: return Color.black.opacity(0.85)
        case .brutalist: return Color(white: 0.95)
        }
    }
    
    var shadowColor: Color {
        switch self {
        case .classic: return .black.opacity(0.4)
        case .neon: return Color(red: 0.0, green: 1.0, blue: 0.8).opacity(0.5)
        case .brutalist: return .black
        }
    }
    
    var borderStyle: AnyView {
        switch self {
        case .classic, .neon:
            return AnyView(EmptyView())
        case .brutalist:
            return AnyView(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.black, lineWidth: 4)
            )
        }
    }
}
