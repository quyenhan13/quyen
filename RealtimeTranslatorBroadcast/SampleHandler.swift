import AVFoundation
import CoreMedia
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private static let appGroupID = "group.com.vteen.RealtimeTranslator"
    private let client = BroadcastSonioxClient()
    private let converter = BroadcastPCMConverter()
    private let defaults = UserDefaults(suiteName: appGroupID)
    private var lastAudioStatusAt: TimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
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

        client.onTranslation = { [weak self] original, translation, isFinal in
            self?.defaults?.set(original, forKey: "broadcast_current_original")
            self?.defaults?.set(translation, forKey: "broadcast_current_translation")
            self?.defaults?.set(isFinal, forKey: "broadcast_is_final")
            self?.defaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_current_translation_at")
            self?.setBroadcastStatus("receiving_translation")
        }
        client.onStatus = { [weak self] status in
            self?.setBroadcastStatus(status)
        }
        client.connect(apiKey: apiKey, sourceLang: sourceLang, targetLang: targetLang)
    }

    private func setBroadcastStatus(_ status: String) {
        defaults?.set(status, forKey: "broadcast_status")
        defaults?.set(Date().timeIntervalSince1970, forKey: "broadcast_status_at")
        defaults?.synchronize()
    }

    private func setAudioActive() {
        let now = Date().timeIntervalSince1970
        defaults?.set(now, forKey: "broadcast_audio_at")
        if now - lastAudioStatusAt > 0.8 {
            lastAudioStatusAt = now
            setBroadcastStatus("sending_audio")
        }
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
        setBroadcastStatus("finished")
        client.disconnect()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .audioApp else { return }
        guard let pcm = converter.convert(sampleBuffer), !pcm.isEmpty else { return }
        setAudioActive()
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
    private let lock = NSLock()
    private var pendingAudio: [Data] = []
    private var configSent = false
    private var configPayload: String = ""
    var onTranslation: ((String, String, Bool) -> Void)?
    var onStatus: ((String) -> Void)?

    func connect(apiKey: String, sourceLang: String, targetLang: String) {
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
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        configPayload = text

        socket?.resume()
        socket?.send(.string(text)) { [weak self] error in
            guard let self else { return }
            self.lock.lock()
            if error == nil {
                self.configSent = true
                self.onStatus?("connected")
                let chunks = self.pendingAudio
                self.pendingAudio.removeAll()
                self.lock.unlock()
                
                for chunk in chunks {
                    self.socket?.send(.data(chunk)) { _ in }
                }
            } else {
                self.lock.unlock()
                self.onStatus?("config_send_failed")
            }
        }
        receiveLoop()
    }

    func sendAudio(_ data: Data) {
        lock.lock()
        guard let socket, socket.state == .running else {
            lock.unlock()
            return
        }
        if configSent {
            lock.unlock()
            socket.send(.data(data)) { _ in }
        } else {
            if pendingAudio.count < 50 {
                pendingAudio.append(data)
            }
            lock.unlock()
        }
    }

    func disconnect() {
        lock.lock()
        configSent = false
        pendingAudio.removeAll()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        lock.unlock()
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

    private func handleResponse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let errCode = json["error_code"] {
            _ = errCode
            onStatus?("soniox_error")
            return
        }

        guard let tokens = json["tokens"] as? [[String: Any]] else { return }

        var currentNonFinalOriginal: [String] = []
        var currentNonFinalTranslation: [String] = []
        var isEndpoint = false

        for token in tokens {
            let tokenText = token["text"] as? String ?? ""
            if tokenText == "<end>" {
                isEndpoint = true
                continue
            }
            guard !tokenText.isEmpty else { continue }

            let isTranslation = (token["translation_status"] as? String == "translation")
            let committed = isCommitted(token)

            if isTranslation {
                if committed {
                    finalTranslationTokens.append(tokenText)
                } else {
                    currentNonFinalTranslation.append(tokenText)
                }
            } else {
                if committed {
                    finalOriginalTokens.append(tokenText)
                } else {
                    currentNonFinalOriginal.append(tokenText)
                }
            }
        }

        let displayOriginal = (finalOriginalTokens + currentNonFinalOriginal).joined()
        let displayTranslation = (finalTranslationTokens + currentNonFinalTranslation).joined()

        let trimmedOriginal = trimSubtitleBuffer(displayOriginal)
        let trimmedTranslation = trimSubtitleBuffer(displayTranslation)

        if !trimmedTranslation.isEmpty || !trimmedOriginal.isEmpty {
            onTranslation?(trimmedOriginal, trimmedTranslation, isEndpoint)
        }

        if isEndpoint {
            finalOriginalTokens.removeAll()
            finalTranslationTokens.removeAll()
        }
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

        guard let format = AVAudioFormat(streamDescription: streamDescription) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        var blockBuffer: CMBlockBuffer?
        var neededSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, neededSize > 0 else { return nil }

        let rawABL = UnsafeMutableRawPointer.allocate(byteCount: neededSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawABL.deallocate() }

        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: rawABL.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: neededSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        pcmBuffer.frameLength = frameCount
        if !copyAudioBuffers(rawABL.assumingMemoryBound(to: AudioBufferList.self), streamDescription: streamDescription, to: pcmBuffer) {
            return nil
        }

        return pcmBuffer
    }

    private func copyAudioBuffers(_ audioBufferList: UnsafeMutablePointer<AudioBufferList>, streamDescription: UnsafePointer<AudioStreamBasicDescription>, to pcmBuffer: AVAudioPCMBuffer) -> Bool {
        let stream = streamDescription.pointee
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let channelCount = Int(pcmBuffer.format.channelCount)
        let frameCount = Int(pcmBuffer.frameLength)
        let isInterleaved = stream.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        if stream.mFormatFlags & kAudioFormatFlagIsFloat != 0, let destination = pcmBuffer.floatChannelData {
            if isInterleaved {
                guard let sourceData = buffers.first?.mData else { return false }
                let source = sourceData.assumingMemoryBound(to: Float.self)
                for frame in 0..<frameCount {
                    for channel in 0..<channelCount {
                        destination[channel][frame] = source[frame * channelCount + channel]
                    }
                }
            } else {
                for channel in 0..<min(channelCount, buffers.count) {
                    guard let sourceData = buffers[channel].mData else { continue }
                    destination[channel].assign(from: sourceData.assumingMemoryBound(to: Float.self), count: frameCount)
                }
            }
            return true
        }

        guard stream.mBitsPerChannel == 16, let destination = pcmBuffer.int16ChannelData else {
            return false
        }

        if isInterleaved {
            guard let sourceData = buffers.first?.mData else { return false }
            let source = sourceData.assumingMemoryBound(to: Int16.self)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    destination[channel][frame] = source[frame * channelCount + channel]
                }
            }
        } else {
            for channel in 0..<min(channelCount, buffers.count) {
                guard let sourceData = buffers[channel].mData else { continue }
                destination[channel].assign(from: sourceData.assumingMemoryBound(to: Int16.self), count: frameCount)
            }
        }
        return true
    }
}
