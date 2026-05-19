import Foundation
import UIKit

@MainActor
final class AutoUpdateManager: ObservableObject {
    static let shared = AutoUpdateManager()

    @Published var availableUpdate: AppUpdate?
    @Published var isChecking = false

    private let releaseURL = URL(string: "https://api.github.com/repos/quyenhan13/iosdich/releases/tags/latest")!
    private let lastPromptedKey = "auto_update_last_prompted_release"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    func checkForUpdates(silent: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: releaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 12

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }

            let release = try decoder.decode(GitHubRelease.self, from: data)
            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".ipa") }) else { return }

            let updateID = "\(release.tagName)-\(asset.updatedAt.timeIntervalSince1970)"
            if silent && UserDefaults.standard.string(forKey: lastPromptedKey) == updateID {
                return
            }

            availableUpdate = AppUpdate(
                id: updateID,
                title: release.name.isEmpty ? "RealtimeTranslator IPA" : release.name,
                downloadURL: asset.browserDownloadURL
            )
        } catch {
            Logger.log("Kiểm tra cập nhật lỗi: \(error.localizedDescription)", level: .error)
        }
    }

    func install(_ update: AppUpdate) {
        UserDefaults.standard.set(update.id, forKey: lastPromptedKey)
        UIApplication.shared.open(update.downloadURL)
        availableUpdate = nil
    }

    func dismiss(_ update: AppUpdate) {
        UserDefaults.standard.set(update.id, forKey: lastPromptedKey)
        availableUpdate = nil
    }
}

struct AppUpdate: Identifiable {
    let id: String
    let title: String
    let downloadURL: URL
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let updatedAt: Date
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case updatedAt = "updated_at"
        case browserDownloadURL = "browser_download_url"
    }
}
