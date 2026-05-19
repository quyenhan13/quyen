import AVFoundation

final class AudioSessionManager {
    static func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setPreferredSampleRate(16000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)
        Logger.log("Đã cấu hình thành công AVAudioSession cho việc thu âm.")
    }

    static func configureForPlaybackOverlay() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try session.setActive(true)
        Logger.log("Đã cấu hình AVAudioSession cho phụ đề nổi PiP.")
    }

    static func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false)
        Logger.log("Đã tắt AVAudioSession.")
    }
}
