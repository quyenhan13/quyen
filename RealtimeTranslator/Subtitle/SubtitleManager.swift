import Foundation

final class SubtitleManager: ObservableObject {
    @Published var currentText: String = ""
    @Published var currentTranslatedText: String = ""
    @Published var historyLines: [SubtitleLine] = []
    
    private var silenceTimer: Timer?
    private var broadcastTimer: Timer?
    private var lastBroadcastTimestamp: TimeInterval = 0
    private let groupDefaults = UserDefaults(suiteName: "group.com.vteen.Transifyr")
    private var confirmedOriginal = ""
    private var confirmedTranslation = ""
    private var activeOriginalSentence = ""
    private var activeTranslationSentence = ""
    private var finalOriginalTokens: [String] = []
    private var finalTranslationTokens: [String] = []

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
        
        let translatedText = words.map { $0.textTranslated ?? "" }.joined(separator: " ")
        
        let isFinal = response.final ?? false

        DispatchQueue.main.async {
            if isFinal {
                let finalLine = SubtitleLine(text: "", textTranslated: translatedText, isFinal: true)
                self.historyLines.append(finalLine)
                
                if self.historyLines.count > 15 {
                    self.historyLines.removeFirst()
                }
                
                self.currentText = ""
                self.currentTranslatedText = ""
            } else {
                self.currentText = ""
                self.currentTranslatedText = translatedText
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

        var currentNonFinalOriginal: [String] = []
        var currentNonFinalTranslation: [String] = []
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
                    currentNonFinalTranslation.append(text)
                }
            } else {
                if token.isCommitted {
                    finalOriginalTokens.append(text)
                } else {
                    currentNonFinalOriginal.append(text)
                }
            }
        }

        let displayOriginal = (finalOriginalTokens + currentNonFinalOriginal).joined()
        let displayTranslation = (finalTranslationTokens + currentNonFinalTranslation).joined()

        let latestOriginal = extractLatestSentence(displayOriginal)
        let latestTranslation = extractLatestSentence(displayTranslation)

        let trimmedOriginal = trimSubtitleBuffer(latestOriginal)
        let trimmedTranslation = trimSubtitleBuffer(latestTranslation)

        if !trimmedTranslation.isEmpty || !trimmedOriginal.isEmpty {
            DispatchQueue.main.async {
                self.currentText = trimmedOriginal
                self.currentTranslatedText = trimmedTranslation
            }
        }

        if isEndpoint {
            let translation = (finalTranslationTokens + currentNonFinalTranslation).joined()
            let original = (finalOriginalTokens + currentNonFinalOriginal).joined()
            let trimmedFinalTranslation = trimSubtitleBuffer(translation)
            let trimmedFinalOriginal = trimSubtitleBuffer(original)
            
            if !trimmedFinalTranslation.isEmpty {
                DispatchQueue.main.async {
                    self.historyLines.append(SubtitleLine(text: trimmedFinalOriginal, textTranslated: trimmedFinalTranslation, isFinal: true))
                    if self.historyLines.count > 15 {
                        self.historyLines.removeFirst()
                    }
                    self.currentText = ""
                    self.currentTranslatedText = ""
                }
            }
            finalOriginalTokens.removeAll()
            finalTranslationTokens.removeAll()
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

    private func extractLatestSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        let delimiters: Set<Character> = [".", "!", "?", "。", "！", "？"]
        
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            index = trimmed.index(before: index)
            let char = trimmed[index]
            if delimiters.contains(char) {
                // Nếu dấu câu ở ngay cuối chuỗi, ta bỏ qua và tìm tiếp dấu câu phía trước
                if index == trimmed.index(before: trimmed.endIndex) {
                    continue
                }
                let nextIndex = trimmed.index(after: index)
                return String(trimmed[nextIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return trimmed
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
        let isFinal = defaults.bool(forKey: "broadcast_is_final")

        resetSilenceTimer()

        if isFinal || (original.isEmpty && translation.isEmpty) {
            let prevTranslation = translation.isEmpty ? currentTranslatedText : translation
            let prevOriginal = original.isEmpty ? currentText : original
            let latestPrevOriginal = extractLatestSentence(prevOriginal)
            let latestPrevTranslation = extractLatestSentence(prevTranslation)
            let trimmedPrevTranslation = trimSubtitleBuffer(latestPrevTranslation)
            let trimmedPrevOriginal = trimSubtitleBuffer(latestPrevOriginal)
            
            if !trimmedPrevTranslation.isEmpty {
                DispatchQueue.main.async {
                    self.historyLines.append(SubtitleLine(text: trimmedPrevOriginal, textTranslated: trimmedPrevTranslation, isFinal: true))
                    if self.historyLines.count > 15 { self.historyLines.removeFirst() }
                    self.currentText = ""
                    self.currentTranslatedText = ""
                }
            }
            return
        }

        let latestOriginal = extractLatestSentence(original)
        let latestTranslation = extractLatestSentence(translation)

        DispatchQueue.main.async {
            self.currentText = latestOriginal
            self.currentTranslatedText = self.trimSubtitleBuffer(latestTranslation)
        }
    }
}
