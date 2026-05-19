import Foundation

final class SubtitleManager: ObservableObject {
    @Published var currentText: String = ""
    @Published var currentTranslatedText: String = ""
    @Published var historyLines: [SubtitleLine] = []
    
    private var silenceTimer: Timer?
    private var broadcastTimer: Timer?
    private var lastBroadcastTimestamp: TimeInterval = 0
    private let groupDefaults = UserDefaults(suiteName: "group.com.vteen.RealtimeTranslator")
    private var confirmedOriginal = ""
    private var confirmedTranslation = ""
    private var activeOriginalSentence = ""
    private var activeTranslationSentence = ""
    private var finalOriginalTokens: [String] = []
    private var finalTranslationTokens: [String] = []
    private var segmentStartedAt = Date()

    private func publishSharedSubtitle(original: String, translation: String) {
        let cleanedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranslation.isEmpty else { return }
        PlayerLayerPiPSubtitleManager.shared.update(translation: cleanedTranslation)
        SystemSubtitleOverlayManager.shared?.update(text: original, translation: cleanedTranslation)
        groupDefaults?.set(original.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "broadcast_current_original")
        groupDefaults?.set(cleanedTranslation, forKey: "broadcast_current_translation")
        groupDefaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_current_translation_at")
        groupDefaults?.synchronize()
    }

    @discardableResult
    func beginBroadcastSession() -> String {
        let sessionID = UUID().uuidString
        clear()
        clearSharedSubtitle(updateTimestamp: true)
        groupDefaults?.set(true, forKey: "broadcast_should_run")
        groupDefaults?.set(sessionID, forKey: "broadcast_session_id")
        groupDefaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_start_requested_at")
        groupDefaults?.set("starting", forKey: "broadcast_status")
        groupDefaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_status_at")
        groupDefaults?.synchronize()
        return sessionID
    }

    func requestBroadcastStop() {
        clear()
        clearSharedSubtitle(updateTimestamp: true)
        groupDefaults?.set(false, forKey: "broadcast_should_run")
        groupDefaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_stop_requested_at")
        groupDefaults?.set("stop_requested", forKey: "broadcast_status")
        groupDefaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_status_at")
        groupDefaults?.synchronize()
    }

    func resetSharedSubtitleCache() {
        clear()
        clearSharedSubtitle(updateTimestamp: true)
    }

    func handleSonioxResponse(_ response: SonioxResponse) {
        if let message = response.errorMessage ?? response.error {
            Logger.log("Soniox lỗi: \(message)", level: .error)
            return
        }

        if let tokens = response.tokens, !tokens.isEmpty {
            handleSonioxTokens(tokens)
            return
        }

        guard let words = response.words, !words.isEmpty else { return }
        
        resetSilenceTimer()
        
        let originalText = words.map { $0.text }.joined(separator: " ")
        let translatedText = words.map { $0.textTranslated ?? "" }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translatedText.isEmpty else { return }
        
        let isFinal = response.final ?? false

        DispatchQueue.main.async {
            if isFinal {
                let finalLine = SubtitleLine(text: originalText, textTranslated: translatedText, isFinal: true)
                self.historyLines.append(finalLine)
                
                if self.historyLines.count > 15 {
                    self.historyLines.removeFirst()
                }
                
                self.currentText = ""
                self.currentTranslatedText = ""
            } else {
                self.currentText = originalText
                self.currentTranslatedText = translatedText
                self.publishSharedSubtitle(original: originalText, translation: translatedText)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.currentText = ""
            self.currentTranslatedText = ""
            self.historyLines.removeAll()
        }
        confirmedOriginal = ""
        confirmedTranslation = ""
        activeOriginalSentence = ""
        activeTranslationSentence = ""
        finalOriginalTokens.removeAll()
        finalTranslationTokens.removeAll()
        segmentStartedAt = Date()
    }

    private func clearSharedSubtitle(updateTimestamp: Bool) {
        PlayerLayerPiPSubtitleManager.shared.update(translation: "")
        SystemSubtitleOverlayManager.shared?.update(text: "", translation: "")
        groupDefaults?.set("", forKey: "broadcast_current_original")
        groupDefaults?.set("", forKey: "broadcast_current_translation")
        if updateTimestamp {
            let now = Date().timeIntervalSince1970
            groupDefaults?.set(now, forKey: "broadcast_current_translation_at")
            lastBroadcastTimestamp = now
        }
        groupDefaults?.synchronize()
    }

    func startBroadcastSubtitleSync() {
        guard broadcastTimer == nil else { return }
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.pullBroadcastSubtitle()
        }
        broadcastTimer?.tolerance = 0.12
        pullBroadcastSubtitle()
    }

    func stopBroadcastSubtitleSync() {
        broadcastTimer?.invalidate()
        broadcastTimer = nil
    }

    private func handleSonioxTokens(_ tokens: [SonioxToken]) {
        resetSilenceTimer()

        var nonFinalOriginal = ""
        var nonFinalTranslation = ""
        var isEndpoint = false

        for token in tokens {
            let text = token.text ?? ""
            if text == "<end>" {
                isEndpoint = true
                continue
            }
            guard !text.isEmpty else { continue }

            if token.isTranslation {
                if token.isCommitted {
                    finalTranslationTokens.append(text)
                } else {
                    nonFinalTranslation += text
                }
            } else if token.isOriginal {
                if token.isCommitted {
                    finalOriginalTokens.append(text)
                } else {
                    nonFinalOriginal += text
                }
            }
        }

        let displayOriginal = trimSubtitleBuffer((finalOriginalTokens.joined() + nonFinalOriginal))
        let displayTranslation = trimSubtitleBuffer((finalTranslationTokens.joined() + nonFinalTranslation))

        if !displayTranslation.isEmpty {
            DispatchQueue.main.async {
                self.currentText = displayOriginal
                self.currentTranslatedText = displayTranslation
                self.publishSharedSubtitle(original: displayOriginal, translation: displayTranslation)
            }
        }

        if isEndpoint || shouldRollSegment(displayOriginal: displayOriginal, displayTranslation: displayTranslation) {
            let translation = displayTranslation
            let original = displayOriginal
            if !translation.isEmpty {
                DispatchQueue.main.async {
                    self.historyLines.append(SubtitleLine(text: original, textTranslated: translation, isFinal: true))
                    if self.historyLines.count > 15 {
                        self.historyLines.removeFirst()
                    }
                }
            }
            finalOriginalTokens.removeAll()
            finalTranslationTokens.removeAll()
            segmentStartedAt = Date()
            DispatchQueue.main.async {
                self.currentText = ""
                self.currentTranslatedText = ""
                self.clearSharedSubtitle(updateTimestamp: true)
            }
        }

        if confirmedOriginal.count > 1800 {
            confirmedOriginal = String(confirmedOriginal.suffix(1200))
        }
        if confirmedTranslation.count > 1800 {
            confirmedTranslation = String(confirmedTranslation.suffix(1200))
        }
    }

    private func flushActiveSentence() {
        let original = activeOriginalSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = activeTranslationSentence.trimmingCharacters(in: .whitespacesAndNewlines)

        activeOriginalSentence = ""
        activeTranslationSentence = ""

        guard !translation.isEmpty else { return }

        DispatchQueue.main.async {
            self.historyLines.append(SubtitleLine(text: original, textTranslated: translation, isFinal: true))
            if self.historyLines.count > 15 {
                self.historyLines.removeFirst()
            }
        }
    }

    private func shouldFlushSentence(_ text: String) -> Bool {
        text.range(of: #"[.!?。！？]\s*$"#, options: .regularExpression) != nil
    }

    private func appendUniqueText(_ base: String, _ addition: String) -> String {
        let cleanAddition = addition.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !cleanAddition.isEmpty else { return base }
        if base.hasSuffix(cleanAddition) {
            return base
        }
        return base + cleanAddition
    }

    private func trimSubtitleBuffer(_ text: String, maxChars: Int = 140) -> String {
        let normalized = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxChars else { return normalized }
        return String(normalized.suffix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldRollSegment(displayOriginal: String, displayTranslation: String) -> Bool {
        guard !displayTranslation.isEmpty else { return false }
        if displayTranslation.count >= 120 { return true }
        if displayOriginal.count >= 160 { return true }
        if Date().timeIntervalSince(segmentStartedAt) >= 8 { return true }
        return displayTranslation.range(of: #"[.!?。！？]\s*$"#, options: .regularExpression) != nil
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentText = ""
                self?.currentTranslatedText = ""
            }
        }
    }

    private func pullBroadcastSubtitle() {
        guard let defaults = groupDefaults else { return }

        let timestamp = defaults.double(forKey: "broadcast_current_translation_at")
        guard timestamp > lastBroadcastTimestamp else { return }
        lastBroadcastTimestamp = timestamp

        let original = defaults.string(forKey: "broadcast_current_original")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let translation = defaults.string(forKey: "broadcast_current_translation")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        resetSilenceTimer()

        // Tín hiệu segment end: cả hai đều rỗng → đưa câu hiện tại vào lịch sử rồi xóa màn hình
        if original.isEmpty && translation.isEmpty {
            let prevTranslation = currentTranslatedText
            DispatchQueue.main.async {
                if !prevTranslation.isEmpty {
                    self.historyLines.append(SubtitleLine(text: "", textTranslated: prevTranslation, isFinal: true))
                    if self.historyLines.count > 15 { self.historyLines.removeFirst() }
                }
                self.currentText = ""
                self.currentTranslatedText = ""
                PlayerLayerPiPSubtitleManager.shared.update(translation: "")
                SystemSubtitleOverlayManager.shared?.update(text: "", translation: "")
            }
            return
        }

        DispatchQueue.main.async {
            self.currentText = ""
            let trimmedTranslation = self.trimSubtitleBuffer(translation)
            self.currentTranslatedText = trimmedTranslation
            PlayerLayerPiPSubtitleManager.shared.update(translation: trimmedTranslation)
            SystemSubtitleOverlayManager.shared?.update(text: "", translation: trimmedTranslation)
        }
    }
}
