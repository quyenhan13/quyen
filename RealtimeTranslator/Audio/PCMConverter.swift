import AVFoundation

final class PCMConverter {
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    init() {
        let targetSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        self.targetFormat = AVAudioFormat(settings: targetSettings)!
    }

    func convertToPCM16Mono16k(buffer: AVAudioPCMBuffer) -> Data? {
        let sourceFormat = buffer.format
        
        if converter == nil {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        
        guard let converter = converter else { return nil }
        
        let ratio = 16000.0 / sourceFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            return nil
        }
        
        var isDataProvided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if isDataProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            isDataProvided = true
            return buffer
        }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            Logger.log("Chuyển đổi PCM lỗi: \(error.localizedDescription)", level: .error)
            return nil
        }
        
        guard let channelData = outputBuffer.int16ChannelData else { return nil }
        let channelDataPointer = channelData[0]
        let dataSize = Int(outputBuffer.frameLength) * 2 // 16-bit = 2 bytes/frame
        
        return Data(bytes: channelDataPointer, count: dataSize)
    }
}
