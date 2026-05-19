import AVFoundation
import CoreMedia
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private static let appGroupID = "group.com.vteen.RealtimeTranslator"
    private let client = BroadcastSonioxClient()
    private let converter = BroadcastPCMConverter()
    private let defaults = UserDefaults(suiteName: appGroupID)
    private var stopRequested = false
    private var stopPollTimer: Timer?

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        stopRequested = false
        clearSharedSubtitle(updateTimestamp: true)
        defaults?.set(true, forKey: "broadcast_should_run")
        if defaults?.string(forKey: "broadcast_session_id") == nil {
            defaults?.set(UUID().uuidString, forKey: "broadcast_session_id")
        }
        setBroadcastStatus("starting")
        let sharedSettings = loadSharedSettingsFile()
        let apiKey = firstNonEmpty(
            defaults?.string(forKey: "soniox_api_key_fallback"),
            sharedSettings["soniox_api_key_fallback"] as? String
        ) ?? ""
        let sourceLang = firstNonEmpty(
            defaults?.string(forKey: "source_language"),
            sharedSettings["source_language"] as? String
        ) ?? "auto"
        let targetLang = firstNonEmpty(
            defaults?.string(forKey: "target_language"),
            sharedSettings["target_language"] as? String
        ) ?? "vi"

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setBroadcastStatus("missing_api_key")
            finishBroadcastWithError(NSError(domain: "TransifyrBroadcast", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Chưa có Soniox API Key. Mở app Transifyr và lưu key trước."
            ]))
            return
        }

        client.onTranslation = { [weak self] original, translation in
            guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self?.defaults?.set(original, forKey: "broadcast_current_original")
            self?.defaults?.set(translation, forKey: "broadcast_current_translation")
            self?.defaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_current_translation_at")
            self?.setBroadcastStatus("receiving_translation")
        }
        client.onStatus = { [weak self] status in
            self?.setBroadcastStatus(status)
        }
        client.connect(apiKey: apiKey, sourceLang: sourceLang, targetLang: targetLang)
        stopPollTimer?.invalidate()
        stopPollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            _ = self?.stopFromContainingAppIfNeeded()
        }
    }

    private func setBroadcastStatus(_ status: String) {
        defaults?.set(status, forKey: "broadcast_status")
        defaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_status_at")
        defaults?.synchronize()
    }

    private func clearSharedSubtitle(updateTimestamp: Bool) {
        defaults?.set("", forKey: "broadcast_current_original")
        defaults?.set("", forKey: "broadcast_current_translation")
        if updateTimestamp {
            defaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_current_translation_at")
        }
        defaults?.synchronize()
    }

    private func shouldStopBroadcast() -> Bool {
        if stopRequested { return false }
        return defaults?.object(forKey: "broadcast_should_run") as? Bool == false
    }

    private func stopFromContainingAppIfNeeded() -> Bool {
        guard shouldStopBroadcast() else { return false }
        stopRequested = true
        setBroadcastStatus("stopping")
        clearSharedSubtitle(updateTimestamp: true)
        client.disconnect()
        finishBroadcastWithError(NSError(domain: "TransifyrBroadcast", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Đã dừng dịch."
        ]))
        return true
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func loadSharedSettingsFile() -> [String: Any] {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return [:]
        }

        let fileURL = containerURL.appendingPathComponent("transifyr_shared_settings.json")
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    override func broadcastFinished() {
        stopPollTimer?.invalidate()
        stopPollTimer = nil
        defaults?.set(false, forKey: "broadcast_should_run")
        clearSharedSubtitle(updateTimestamp: true)
        setBroadcastStatus("finished")
        client.disconnect()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard !stopFromContainingAppIfNeeded() else { return }
        guard sampleBufferType == .audioApp else { return }
        guard let pcm = converter.convert(sampleBuffer), !pcm.isEmpty else { return }
        setBroadcastStatus("sending_audio")
        client.sendAudio(pcm)
    }
}

private final class BroadcastSonioxClient {
    private var socket: URLSessionWebSocketTask?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    private var pendingAudio: [Data] = []
    private var configSent = false
    private var configPayload: String = ""
    private let automaticLanguageHints = ["en", "vi", "zh", "ja", "ko", "th", "id", "es", "fr", "de", "ru"]
    var onTranslation: ((String, String) -> Void)?
    var onStatus: ((String) -> Void)?

    func connect(apiKey: String, sourceLang: String, targetLang: String) {
        resetSegment()
        onStatus?("connecting")
        let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
        socket = session.webSocketTask(with: url)

        let sourceCode = sourceLang == "auto" ? nil : sourceLang
        var payload: [String: Any] = [
            "api_key": apiKey,
            "model": "stt-rt-v4",
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1,
            "enable_endpoint_detection": true,
            "enable_language_identification": sourceCode == nil,
            "max_endpoint_delay_ms": 80,
            "translation": [
                "type": "one_way",
                "target_language": targetLang
            ]
        ]
        if let sourceCode {
            payload["language_hints"] = [sourceCode]
        } else {
            payload["language_hints"] = automaticLanguageHints
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        configPayload = text

        socket?.resume()
        socket?.send(.string(text)) { [weak self] error in
            guard let self else { return }
            if error == nil {
                self.configSent = true
                self.onStatus?("connected")
                for chunk in self.pendingAudio {
                    self.socket?.send(.data(chunk)) { _ in }
                }
                self.pendingAudio.removeAll()
            } else {
                self.onStatus?("config_send_failed")
            }
        }
        receiveLoop()
    }

    func sendAudio(_ data: Data) {
        guard let socket, socket.state == .running else { return }
        if configSent {
            socket.send(.data(data)) { _ in }
        } else {
            if pendingAudio.count < 50 {
                pendingAudio.append(data)
            }
        }
    }

    func disconnect() {
        configSent = false
        pendingAudio.removeAll()
        resetSegment()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func receiveLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleResponse(text)
                }
                self.receiveLoop()
            case .failure:
                break
            }
        }
    }

    // Theo Soniox docs: final tokens phải được ACCUMULATE qua nhiều response
    // Non-final tokens RESET mỗi response
    // Translation tokens chỉ xuất hiện sau endpoint và luôn là is_final=true
    private var finalOriginalTokens: [String] = []
    private var finalTranslationTokens: [String] = []
    private var segmentStartedAt = Date()

    private func handleResponse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let errCode = json["error_code"] {
            _ = errCode
            onStatus?("soniox_error")
            return
        }

        guard let tokens = json["tokens"] as? [[String: Any]] else { return }

        var nonFinalOriginal = ""
        var nonFinalTranslation = ""
        var isEndpoint = false

        for token in tokens {
            let tokenText = token["text"] as? String ?? ""
            if tokenText == "<end>" {
                isEndpoint = true
                continue
            }
            guard !tokenText.isEmpty else { continue }

            let status = (token["translation_status"] as? String)?.lowercased()
            if status == "translation" {
                if isCommitted(token) {
                    finalTranslationTokens.append(tokenText)
                } else {
                    nonFinalTranslation += tokenText
                }
            } else if status == nil || status == "none" || status == "original" {
                if isCommitted(token) {
                    finalOriginalTokens.append(tokenText)
                } else {
                    nonFinalOriginal += tokenText
                }
            }
        }

        let displayOriginal = trimSubtitleBuffer(finalOriginalTokens.joined() + nonFinalOriginal)
        let displayTranslation = trimSubtitleBuffer(finalTranslationTokens.joined() + nonFinalTranslation)
        if !displayTranslation.isEmpty {
            onTranslation?(displayOriginal, displayTranslation)
        }

        if isEndpoint || shouldRollSegment(displayOriginal: displayOriginal, displayTranslation: displayTranslation) {
            resetSegment()
        }
    }

    private func shouldRollSegment(displayOriginal: String, displayTranslation: String) -> Bool {
        guard !displayTranslation.isEmpty else { return false }
        if displayTranslation.count >= 120 { return true }
        if displayOriginal.count >= 160 { return true }
        if Date().timeIntervalSince(segmentStartedAt) >= 8 { return true }
        return displayTranslation.range(of: #"[.!?。！？]\s*$"#, options: .regularExpression) != nil
    }

    private func resetSegment() {
        finalOriginalTokens.removeAll()
        finalTranslationTokens.removeAll()
        segmentStartedAt = Date()
    }

    private func isCommitted(_ token: [String: Any]) -> Bool {
        (token["is_final"] as? Bool ?? false)
            || (token["final"] as? Bool ?? false)
            || (token["is_stable"] as? Bool ?? false)
            || (token["stable"] as? Bool ?? false)
    }

    private func trimSubtitleBuffer(_ text: String, maxChars: Int = 140) -> String {
        let normalized = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxChars else { return normalized }
        return String(normalized.suffix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class BroadcastPCMConverter {
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    func convert(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let inputBuffer = makePCMBuffer(from: sampleBuffer) else { return nil }

        if converter == nil || converter?.inputFormat != inputBuffer.format {
            converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat)
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else { return nil }

        var didProvideData = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if didProvideData {
                status.pointee = .noDataNow
                return nil
            }
            didProvideData = true
            status.pointee = .haveData
            return inputBuffer
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil, let channelData = outputBuffer.int16ChannelData else { return nil }
        return Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size)
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let stream = streamDescription.pointee
        guard let format = AVAudioFormat(streamDescription: streamDescription) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        pcmBuffer.frameLength = frameCount

        let bytesPerFrame = Int(stream.mBytesPerFrame) > 1 ? Int(stream.mBytesPerFrame) : 1
        let byteCount = Int(frameCount) * bytesPerFrame

        if stream.mFormatFlags & kAudioFormatFlagIsFloat != 0, let floatChannelData = pcmBuffer.floatChannelData {
            guard let sourceData = audioBufferList.mBuffers.mData else { return nil }
            let source = sourceData.assumingMemoryBound(to: Float.self)
            let count = min(Int(frameCount), byteCount / MemoryLayout<Float>.size)
            floatChannelData[0].assign(from: source, count: count)
        } else if let int16ChannelData = pcmBuffer.int16ChannelData {
            guard let sourceData = audioBufferList.mBuffers.mData else { return nil }
            let source = sourceData.assumingMemoryBound(to: Int16.self)
            let count = min(Int(frameCount), byteCount / MemoryLayout<Int16>.size)
            int16ChannelData[0].assign(from: source, count: count)
        } else {
            return nil
        }

        return pcmBuffer
    }
}
