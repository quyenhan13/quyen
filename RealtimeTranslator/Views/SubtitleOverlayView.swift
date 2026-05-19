import SwiftUI

struct SubtitleOverlayView: View {
    @ObservedObject var settings = AppSettings.shared
    let text: String
    let translation: String
    
    private var style: SubtitleStyle {
        SubtitleStyle(rawValue: settings.overlayStyle) ?? .classic
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if !text.isEmpty {
                Text(text)
                    .italic()
                    .font(style.font)
                    .foregroundColor(style.foregroundColor.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            
            if !translation.isEmpty {
                Text(translation)
                    .font(style.font)
                    .foregroundColor(style.foregroundColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(style.backgroundColor)
        .cornerRadius(style == .brutalist ? 0 : 16)
        .overlay(style.borderStyle)
        .shadow(color: style.shadowColor, radius: style == .brutalist ? 0 : 8, x: style == .brutalist ? 6 : 0, y: style == .brutalist ? 6 : 4)
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: translation)
    }
}
