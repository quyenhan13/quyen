import Foundation

struct SonioxConfig: Codable {
    let apiKey: String
    let model: String
    let audioFormat: String
    let sampleRate: Int
    let numChannels: Int
    let enableEndpointDetection: Bool
    let enableLanguageIdentification: Bool
    let maxEndpointDelayMs: Int
    let languageHints: [String]?
    let translation: TranslationConfig?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case model
        case audioFormat = "audio_format"
        case sampleRate = "sample_rate"
        case numChannels = "num_channels"
        case enableEndpointDetection = "enable_endpoint_detection"
        case enableLanguageIdentification = "enable_language_identification"
        case maxEndpointDelayMs = "max_endpoint_delay_ms"
        case languageHints = "language_hints"
        case translation
    }
}

struct TranslationConfig: Codable {
    let type: String
    let targetLanguage: String

    enum CodingKeys: String, CodingKey {
        case type
        case targetLanguage = "target_language"
    }
}
