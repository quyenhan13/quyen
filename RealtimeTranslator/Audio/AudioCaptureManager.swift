import AVFoundation

final class AudioCaptureManager: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let converter = PCMConverter()
    private let queue = DispatchQueue(label: "com.vteen.audiocapture")
    
    var onPCMData: ((Data) -> Void)?
    
    @Published var isRecording = false

    func startCapture() throws {
        guard !isRecording else { return }
        
        try AudioSessionManager.configureForRecording()
        BackgroundKeepAliveManager.shared.begin()
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 3200, format: inputFormat) { [weak self] buffer, _ in
            self?.queue.async {
                if let pcmData = self?.converter.convertToPCM16Mono16k(buffer: buffer) {
                    if !pcmData.isEmpty {
                        self?.onPCMData?(pcmData)
                    }
                }
            }
        }
        
        try audioEngine.start()
        DispatchQueue.main.async {
            self.isRecording = true
        }
        Logger.log("Bắt đầu thu âm thời gian thực.")
    }

    func stopCapture() {
        guard isRecording else { return }
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        try? AudioSessionManager.deactivate()
        BackgroundKeepAliveManager.shared.end()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        Logger.log("Đã dừng thu âm.")
    }
}
