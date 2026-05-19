import Foundation

struct SubtitleLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let textTranslated: String
    var isFinal: Bool
    let timestamp = Date()
}
