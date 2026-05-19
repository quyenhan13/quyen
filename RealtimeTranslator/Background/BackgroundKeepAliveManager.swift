import AVFoundation
import UIKit

final class BackgroundKeepAliveManager {
    static let shared = BackgroundKeepAliveManager()

    private var taskId: UIBackgroundTaskIdentifier = .invalid
    private var silentPlayer: AVAudioPlayer?

    private init() {}

    func begin() {
        startSilentAudioLoop()
        guard taskId == .invalid else { return }

        taskId = UIApplication.shared.beginBackgroundTask(withName: "RealtimeTranslatorAudio") { [weak self] in
            self?.end()
        }

        if taskId == .invalid {
            Logger.log("Không thể bắt đầu background task.", level: .error)
        } else {
            Logger.log("Đã bắt đầu background task cho realtime audio.")
        }
    }

    func end() {
        stopSilentAudioLoop()
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        taskId = .invalid
        Logger.log("Đã kết thúc background task.")
    }

    private func startSilentAudioLoop() {
        guard silentPlayer == nil else { return }

        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("transifyr-silence.wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                try makeSilentWavData().write(to: url, options: .atomic)
            }

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            silentPlayer = player
            Logger.log("Đã bật audio loop im lặng để giữ phiên chạy nền.")
        } catch {
            Logger.log("Không thể bật audio loop nền: \(error.localizedDescription)", level: .error)
        }
    }

    private func stopSilentAudioLoop() {
        silentPlayer?.stop()
        silentPlayer = nil
    }

    private func makeSilentWavData(sampleRate: UInt32 = 8000, durationSeconds: UInt32 = 1) -> Data {
        let sampleCount = sampleRate * durationSeconds
        let dataSize = sampleCount * 2
        var data = Data()

        func appendString(_ value: String) {
            data.append(value.data(using: .ascii)!)
        }

        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: MemoryLayout<UInt16>.size))
        }

        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: MemoryLayout<UInt32>.size))
        }

        appendString("RIFF")
        appendUInt32(36 + dataSize)
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(sampleRate)
        appendUInt32(sampleRate * 2)
        appendUInt16(2)
        appendUInt16(16)
        appendString("data")
        appendUInt32(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))

        return data
    }
}
