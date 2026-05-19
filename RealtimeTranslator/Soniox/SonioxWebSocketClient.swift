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
    private var pendingWebSocketTask: URLSessionWebSocketTask?
    
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
    
    private var keepaliveTimer: Timer?
    private var sessionTimer: Timer?
    private var recentTranslations: [String] = []
    
    var onTranslationResult: ((SonioxResponse) -> Void)?
    var onError: ((String) -> Void)?

    deinit {
        stopKeepalive()
        stopSessionTimer()
    }

    func connect(apiKey: String, sourceLang: String, targetLang: String) {
        guard connectionState == .disconnected else { return }
        lastAPIKey = apiKey
        lastSourceLang = sourceLang
        lastTargetLang = targetLang
        manuallyDisconnected = false
        reconnectWorkItem?.cancel()
        
        recentTranslations.removeAll()
        stopKeepalive()
        stopSessionTimer()
        
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }
        
        let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        
        let newTask = urlSession.webSocketTask(with: request)
        webSocketTask = newTask
        newTask.resume()
        
        Logger.log("Đang kết nối tới Soniox WebSocket...")
        
        sendConfigTo(newTask, apiKey: apiKey, sourceLang: sourceLang, targetLang: targetLang, contextText: nil)
        startListeningOn(newTask)
    }

    func disconnect() {
        manuallyDisconnected = true
        reconnectWorkItem?.cancel()
        stopKeepalive()
        stopSessionTimer()
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        pendingWebSocketTask?.cancel(with: .normalClosure, reason: nil)
        pendingWebSocketTask = nil
        
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

    private func sendConfigTo(_ task: URLSessionWebSocketTask, apiKey: String, sourceLang: String, targetLang: String, contextText: String?) {
        let modelName = "stt-rt-v4"
        let sourceCode = sourceLang == "auto" ? nil : sourceLang
        let translation = TranslationConfig(type: "one_way", targetLanguage: targetLang)
        
        let context = contextText.map { ContextConfig(text: $0) }
        
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
            translation: translation,
            context: context
        )
        
        do {
            let data = try jsonEncoder.encode(config)
            if let jsonString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                task.send(message) { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        Logger.log("Gửi config bị lỗi: \(error.localizedDescription)", level: .error)
                        if task == self.webSocketTask {
                            self.handleError(error.localizedDescription)
                        } else if task == self.pendingWebSocketTask {
                            self.pendingWebSocketTask = nil
                        }
                    } else {
                        Logger.log("Gửi cấu hình Soniox thành công.")
                        DispatchQueue.main.async {
                            if task == self.webSocketTask {
                                self.reconnectAttempts = 0
                                self.connectionState = .connected
                                self.startKeepalive()
                                self.startSessionTimer()
                            } else if task == self.pendingWebSocketTask {
                                let oldTask = self.webSocketTask
                                self.webSocketTask = task
                                self.pendingWebSocketTask = nil
                                
                                oldTask?.cancel(with: .normalClosure, reason: nil)
                                Logger.log("Seamless Reset hoàn thành! Đã chuyển sang WebSocket mới.")
                                
                                self.reconnectAttempts = 0
                                self.startKeepalive()
                                self.startSessionTimer()
                            }
                        }
                    }
                }
            }
        } catch {
            Logger.log("Encode config lỗi: \(error.localizedDescription)", level: .error)
            if task == self.webSocketTask {
                handleError(error.localizedDescription)
            }
        }
    }

    private func startListeningOn(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            guard task == self.webSocketTask || task == self.pendingWebSocketTask else { return }
            
            switch result {
            case .failure(let error):
                Logger.log("Nhận tin nhắn lỗi: \(error.localizedDescription)", level: .error)
                if task == self.webSocketTask {
                    self.handleError(error.localizedDescription)
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    if let response = SonioxTokenParser.parse(text) {
                        if let tokens = response.tokens {
                            var transText = ""
                            for token in tokens {
                                if token.isTranslation && token.isCommitted {
                                    transText += token.text ?? ""
                                }
                            }
                            if !transText.isEmpty {
                                self.addToHistory(transText)
                            }
                        }
                        DispatchQueue.main.async {
                            self.onTranslationResult?(response)
                        }
                    }
                case .data(let data):
                    Logger.log("Nhận dữ liệu binary từ WebSocket (không mong đợi): \(data.count) bytes")
                @unknown default:
                    break
                }
                self.startListeningOn(task)
            }
        }
    }

    private func seamlessReset() {
        guard !manuallyDisconnected, !lastAPIKey.isEmpty, connectionState == .connected else { return }
        Logger.log("Bắt đầu tự động Seamless Reset (Make-Before-Break)...")
        
        let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        
        let newTask = urlSession.webSocketTask(with: request)
        pendingWebSocketTask = newTask
        newTask.resume()
        
        sendConfigTo(newTask, apiKey: lastAPIKey, sourceLang: lastSourceLang, targetLang: lastTargetLang, contextText: getCarryover())
        startListeningOn(newTask)
    }

    private func startKeepalive() {
        stopKeepalive()
        DispatchQueue.main.async { [weak self] in
            self?.keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                self?.sendKeepalive()
            }
        }
    }

    private func stopKeepalive() {
        DispatchQueue.main.async { [weak self] in
            self?.keepaliveTimer?.invalidate()
            self?.keepaliveTimer = nil
        }
    }

    private func sendKeepalive() {
        guard connectionState == .connected else { return }
        let keepaliveMsg = "{\"type\":\"keepalive\"}"
        let message = URLSessionWebSocketTask.Message.string(keepaliveMsg)
        webSocketTask?.send(message) { error in
            if let error = error {
                Logger.log("Gửi keepalive lỗi: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func startSessionTimer() {
        stopSessionTimer()
        DispatchQueue.main.async { [weak self] in
            self?.sessionTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: false) { [weak self] _ in
                self?.seamlessReset()
            }
        }
    }

    private func stopSessionTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.sessionTimer?.invalidate()
            self?.sessionTimer = nil
        }
    }

    private func addToHistory(_ text: String) {
        recentTranslations.append(text)
        var total = recentTranslations.reduce(0) { $0 + $1.count }
        while total > 500 && recentTranslations.count > 1 {
            let removed = recentTranslations.removeFirst()
            total -= removed.count
        }
    }

    private func getCarryover() -> String? {
        if recentTranslations.isEmpty { return nil }
        return recentTranslations.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleError(_ errorStr: String) {
        guard !manuallyDisconnected else { return }
        
        // Cancel only the current webSocketTask
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        stopKeepalive()
        stopSessionTimer()

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
