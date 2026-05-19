import Foundation

struct SonioxResponse: Codable {
    let tokens: [SonioxToken]?
    let words: [SonioxWord]?
    let final: Bool?
    let error: String?
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case tokens
        case words
        case final
        case error
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

struct SonioxToken: Codable {
    let text: String?
    let translationStatus: String?
    let isFinal: Bool?
    let final: Bool?
    let isStable: Bool?
    let stable: Bool?

    var isTranslation: Bool {
        translationStatus == "translation"
    }

    var isCommitted: Bool {
        (isFinal ?? false) || (final ?? false) || (isStable ?? false) || (stable ?? false)
    }

    enum CodingKeys: String, CodingKey {
        case text
        case translationStatus = "translation_status"
        case isFinal = "is_final"
        case final
        case isStable = "is_stable"
        case stable
    }
}

struct SonioxWord: Codable, Identifiable {
    var id: String { text + "\(startMs)" }
    let text: String
    let startMs: Int
    let durationMs: Int
    let isFinal: Bool?
    let textTranslated: String?

    enum CodingKeys: String, CodingKey {
        case text
        case startMs = "start_ms"
        case durationMs = "duration_ms"
        case isFinal = "is_final"
        case textTranslated = "text_translated"
    }
}
