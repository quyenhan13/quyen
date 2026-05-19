import Foundation

struct SonioxTokenParser {
    static func parse(_ text: String) -> SonioxResponse? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(SonioxResponse.self, from: data)
        } catch {
            Logger.log("Lỗi decode JSON Soniox: \(error.localizedDescription)", level: .error)
            return nil
        }
    }
}
