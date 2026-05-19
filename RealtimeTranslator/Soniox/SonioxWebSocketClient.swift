import Foundation

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

extension ConnectionState: Equatable {
    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.connecting, .connecting):
            return true
        case (.connected, .connected):
            return true
        case (.error(let lErr), .error(let rErr)):
            return lErr == rErr
        default:
            return false
        }
    }
}

final class SonioxWebSocketClient: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
    private let jsonEncoder = JSONEncoder()
    private var reconnectAttempts = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var lastAPIKey = ""
    private var lastSourceLang = "auto"
    private var lastTargetLang = "vi"
    private var manuallyDisconnected = false
    private let automaticLanguageHints = ["en", "vi", "zh", "ja", "ko", "th", "id", "es", "fr", "de", "ru"]
    
    var onTranslationResult: ((SonioxResponse) -> Void)?
    var onError: ((String) -> Void)?

    func connect(apiKey: String, sourceLang: String, targetLang: String) {
        guard connectionState == .disconnected else { return }
        lastAPIKey = apiKey
        lastSourceLang = sourceLang
        lastTargetLang = targetLang
        manuallyDisconnected = false
        reconnectWorkItem?.cancel()
        
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }
        
        let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        Logger.log("Đang kết nối tới Soniox WebSocket...")
        
        sendConfig(apiKey: apiKey, sourceLang: sourceLang, targetLang: targetLang)
        startListening()
    }

    func disconnect() {
        manuallyDisconnected = true
        reconnectWorkItem?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
        Logger.log("Đã ngắt kết nối WebSocket Soniox.")
    }

    func sendAudioChunk(_ data: Data) {
        guard connectionState == .connected else { return }
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                Logger.log("Gửi audio chunk bị lỗi: \(error.localizedDescription)", level: .error)
                self?.handleError(error.localizedDescription)
            }
        }
    }

    private func sendConfig(apiKey: String, sourceLang: String, targetLang: String) {
        let modelName = "stt-rt-v4"
        
        let sourceCode = sourceLang == "auto" ? nil : sourceLang
        let translation = TranslationConfig(type: "one_way", targetLanguage: targetLang)
        let config = SonioxConfig(
            apiKey: apiKey,
            model: modelName,
            audioFormat: "pcm_s16le",
            sampleRate: 16000,
            numChannels: 1,
            enableEndpointDetection: true,
            enableLanguageIdentification: sourceCode == nil,
            maxEndpointDelayMs: 80,
            languageHints: sourceCode.map { [$0] } ?? automaticLanguageHints,
            translation: translation
        )
        
        do {
            let data = try jsonEncoder.encode(config)
            if let jsonString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(message) { [weak self] error in
                    if let error = error {
                        Logger.log("Gửi config bị lỗi: \(error.localizedDescription)", level: .error)
                        self?.handleError(error.localizedDescription)
                    } else {
                        Logger.log("Gửi cấu hình Soniox thành công.")
                        self?.reconnectAttempts = 0
                        DispatchQueue.main.async {
                            self?.connectionState = .connected
                        }
                    }
                }
            }
        } catch {
            Logger.log("Encode config lỗi: \(error.localizedDescription)", level: .error)
            handleError(error.localizedDescription)
        }
    }

    private func startListening() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                Logger.log("Nhận tin nhắn lỗi: \(error.localizedDescription)", level: .error)
                self.handleError(error.localizedDescription)
            case .success(let message):
                switch message {
                case .string(let text):
                    if let response = SonioxTokenParser.parse(text) {
                        DispatchQueue.main.async {
                            self.onTranslationResult?(response)
                        }
                    }
                case .data(let data):
                    Logger.log("Nhận dữ liệu binary từ WebSocket (không mong đợi): \(data.count) bytes")
                @unknown default:
                    break
                }
                self.startListening()
            }
        }
    }

    private func handleError(_ errorStr: String) {
        guard !manuallyDisconnected else { return }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        if shouldRetry(errorStr), reconnectAttempts < 6 {
            scheduleReconnect(reason: errorStr)
            return
        }

        DispatchQueue.main.async {
            self.connectionState = .error(errorStr)
            self.onError?(errorStr)
        }
        disconnect()
    }

    private func shouldRetry(_ errorStr: String) -> Bool {
        let normalized = errorStr.lowercased()
        return normalized.contains("offline")
            || normalized.contains("network")
            || normalized.contains("timed out")
            || normalized.contains("lost")
            || normalized.contains("not connected")
            || normalized.contains("cannot connect")
    }

    private func scheduleReconnect(reason: String) {
        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 1.5, 8.0)
        Logger.log("Soniox tạm mất kết nối (\(reason)). Thử nối lại lần \(reconnectAttempts) sau \(delay)s.")

        DispatchQueue.main.async {
            self.connectionState = .connecting
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.manuallyDisconnected, !self.lastAPIKey.isEmpty else { return }
            DispatchQueue.main.async {
                self.connectionState = .disconnected
            }
            self.connect(apiKey: self.lastAPIKey, sourceLang: self.lastSourceLang, targetLang: self.lastTargetLang)
        }
        reconnectWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
    }
}
