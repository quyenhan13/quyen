import Foundation

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let appGroupID = "group.com.vteen.RealtimeTranslator"
    
    @Published var sourceLanguage: String {
        didSet {
            UserDefaults.standard.set(sourceLanguage, forKey: "source_language")
            groupDefaults?.set(sourceLanguage, forKey: "source_language")
            groupDefaults?.synchronize()
            _ = syncSharedSettings()
        }
    }
    
    @Published var targetLanguage: String {
        didSet {
            UserDefaults.standard.set(targetLanguage, forKey: "target_language")
            groupDefaults?.set(targetLanguage, forKey: "target_language")
            groupDefaults?.synchronize()
            _ = syncSharedSettings()
        }
    }
    
    @Published var overlayStyle: String {
        didSet { UserDefaults.standard.set(overlayStyle, forKey: "overlay_style") }
    }

    @Published var showOriginalSubtitle: Bool {
        didSet {
            UserDefaults.standard.set(showOriginalSubtitle, forKey: "show_original_subtitle")
            groupDefaults?.set(showOriginalSubtitle, forKey: "show_original_subtitle")
            groupDefaults?.synchronize()
            _ = syncSharedSettings()
        }
    }

    private let groupDefaults = UserDefaults(suiteName: appGroupID)

    private init() {
        self.sourceLanguage = UserDefaults.standard.string(forKey: "source_language") ?? "auto"
        self.targetLanguage = UserDefaults.standard.string(forKey: "target_language") ?? "vi"
        self.overlayStyle = UserDefaults.standard.string(forKey: "overlay_style") ?? "Classic"
        self.showOriginalSubtitle = UserDefaults.standard.object(forKey: "show_original_subtitle") as? Bool ?? false
        _ = syncSharedSettings()
    }
    
    var apiKey: String {
        get {
            firstNonEmpty(
                KeychainStore.shared.load(forKey: "soniox_api_key"),
                UserDefaults.standard.string(forKey: "soniox_api_key_fallback"),
                groupDefaults?.string(forKey: "soniox_api_key_fallback")
            ) ?? ""
        }
        set {
            _ = saveAPIKey(newValue)
        }
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedValue.isEmpty else {
            Logger.log("Bo qua luu API Key rong.")
            return false
        }

        UserDefaults.standard.set(cleanedValue, forKey: "soniox_api_key_fallback")
        groupDefaults?.set(cleanedValue, forKey: "soniox_api_key_fallback")
        let savedToKeychain = KeychainStore.shared.save(cleanedValue, forKey: "soniox_api_key")
        _ = syncSharedSettings()
        Logger.log(savedToKeychain ? "Đã lưu API Key vào Keychain." : "Keychain lỗi, đã lưu API Key vào UserDefaults fallback.")
        return savedToKeychain
    }

    @discardableResult
    func syncSharedSettings() -> Bool {
        let key = firstNonEmpty(
            KeychainStore.shared.load(forKey: "soniox_api_key"),
            UserDefaults.standard.string(forKey: "soniox_api_key_fallback"),
            groupDefaults?.string(forKey: "soniox_api_key_fallback")
        ) ?? ""

        if !key.isEmpty {
            UserDefaults.standard.set(key, forKey: "soniox_api_key_fallback")
            groupDefaults?.set(key, forKey: "soniox_api_key_fallback")
        }

        UserDefaults.standard.set(sourceLanguage, forKey: "source_language")
        UserDefaults.standard.set(targetLanguage, forKey: "target_language")
        UserDefaults.standard.set(showOriginalSubtitle, forKey: "show_original_subtitle")
        groupDefaults?.set(sourceLanguage, forKey: "source_language")
        groupDefaults?.set(targetLanguage, forKey: "target_language")
        groupDefaults?.set(showOriginalSubtitle, forKey: "show_original_subtitle")
        UserDefaults.standard.synchronize()
        groupDefaults?.synchronize()
        writeSharedSettingsFile(apiKey: key)
        return !key.isEmpty
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func writeSharedSettingsFile(apiKey: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            Logger.log("Khong mo duoc App Group container de ghi shared settings.")
            return
        }

        let payload: [String: Any] = [
            "soniox_api_key_fallback": apiKey,
            "source_language": sourceLanguage,
            "target_language": targetLanguage,
            "show_original_subtitle": showOriginalSubtitle
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            try data.write(to: containerURL.appendingPathComponent("transifyr_shared_settings.json"), options: .atomic)
        } catch {
            Logger.log("Khong ghi duoc shared settings file: \(error.localizedDescription)")
        }
    }
}
