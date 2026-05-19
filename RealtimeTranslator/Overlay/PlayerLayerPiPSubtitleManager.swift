import AVFoundation
import AVKit
import UIKit

final class PlayerLayerPiPSubtitleManager: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PlayerLayerPiPSubtitleManager()

    private let sourceView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?
    private var subtitleView: UILabel?
    private var pendingTranslation = ""
    private var activeWindow: UIWindow?
    private var pipStartAttempts = 0
    private var pipStartWorkItem: DispatchWorkItem?
    private var subtitleAttachAttempts = 0
    private var subtitleAttachWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        sourceView.alpha = 0.01
        sourceView.isUserInteractionEnabled = false
        playerLayer.frame = sourceView.bounds
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        sourceView.layer.addSublayer(playerLayer)
    }

    var isActive: Bool {
        pipController?.isPictureInPictureActive == true
    }

    func start() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            Logger.log("PlayerLayer PiP is not supported.", level: .error)
            return
        }

        do {
            try AudioSessionManager.configureForPlaybackOverlay()
        } catch {
            Logger.log("Cannot configure audio session for PlayerLayer PiP: \(error.localizedDescription)", level: .error)
        }

        attachSourceViewIfNeeded()
        setupPlayerIfNeeded()
        setupPiPIfNeeded()
        player?.play()

        guard pipController?.isPictureInPictureActive != true else { return }
        pipStartAttempts = 0
        schedulePiPStartAttempt(after: 0.2)
    }

    func stop() {
        pipStartWorkItem?.cancel()
        pipStartWorkItem = nil
        subtitleAttachWorkItem?.cancel()
        subtitleAttachWorkItem = nil
        pipStartAttempts = 0
        subtitleAttachAttempts = 0
        pipController?.stopPictureInPicture()
        player?.pause()
        cleanupSubtitleView()
    }

    func update(translation: String) {
        let cleaned = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            self.pendingTranslation = cleaned
            self.subtitleView?.text = cleaned
            self.subtitleView?.isHidden = cleaned.isEmpty
            self.subtitleView?.invalidateIntrinsicContentSize()
            if self.pipController?.isPictureInPictureActive == true, self.subtitleView == nil {
                self.scheduleSubtitleAttach(after: 0.05)
            }
        }
    }

    private func attachSourceViewIfNeeded() {
        guard sourceView.superview == nil else { return }
        guard let window = currentKeyWindow() else {
            Logger.log("No window available for PlayerLayer PiP source view.", level: .error)
            return
        }
        window.addSubview(sourceView)
    }

    private func setupPlayerIfNeeded() {
        guard player == nil else { return }
        let item = makeDummyPlayerItem()
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.allowsExternalPlayback = true
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restartDummyVideo),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        self.player = player
        playerLayer.player = player
    }

    private func setupPiPIfNeeded() {
        guard pipController == nil else { return }
        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            Logger.log("Cannot create PlayerLayer PiP controller.", level: .error)
            return
        }
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.setValue(1, forKey: "controlsStyle")
        pipController = controller
    }

    private func schedulePiPStartAttempt(after delay: TimeInterval) {
        pipStartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptStartPiP()
        }
        pipStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func attemptStartPiP() {
        guard pipController?.isPictureInPictureActive != true else { return }
        if pipController?.isPictureInPicturePossible == true {
            pipController?.startPictureInPicture()
            return
        }

        pipStartAttempts += 1
        guard pipStartAttempts < 12 else {
            Logger.log("PlayerLayer PiP not possible after \(pipStartAttempts) attempts.", level: .error)
            return
        }
        schedulePiPStartAttempt(after: 0.25)
    }

    private func makeDummyPlayerItem() -> AVPlayerItem {
        if let url = makeBlackVideoURL() {
            return AVPlayerItem(url: url)
        }
        return AVPlayerItem(asset: makeSilentVideoComposition())
    }

    private func makeBlackVideoURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transifyr-pip-black.mp4")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 320,
                AVVideoHeightKey: 180
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: attributes
            )

            guard writer.canAdd(input) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            writer.add(input)
            guard writer.startWriting() else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            writer.startSession(atSourceTime: .zero)

            guard let buffer = makeBlackPixelBuffer() else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            adaptor.append(buffer, withPresentationTime: .zero)
            adaptor.append(buffer, withPresentationTime: CMTime(seconds: 1, preferredTimescale: 30))
            input.markAsFinished()

            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 3)
            guard writer.status == .completed else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return url
        } catch {
            Logger.log("Cannot create PlayerLayer PiP dummy video: \(error.localizedDescription)", level: .error)
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    private func makeBlackPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            320,
            180,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: 320,
                height: 180,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        return pixelBuffer
    }

    private func makeSilentVideoComposition() -> AVComposition {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return composition
        }

        let duration = CMTime(seconds: 3600, preferredTimescale: 600)
        track.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: duration))
        return composition
    }

    @objc private func restartDummyVideo() {
        player?.seek(to: .zero)
        player?.play()
    }

    private func makeSubtitleView(in window: UIWindow) -> UILabel {
        let label = PaddedSubtitleLabel()
        label.contentInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.textColor = .white
        label.font = .systemFont(ofSize: 15.5, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = min(window.bounds.width * 0.74, 360)
        label.layer.cornerRadius = 12
        label.layer.zPosition = CGFloat.greatestFiniteMagnitude
        label.clipsToBounds = true
        label.text = pendingTranslation
        label.isHidden = pendingTranslation.isEmpty
        label.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            label.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, multiplier: 0.78),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
            label.heightAnchor.constraint(lessThanOrEqualToConstant: 62)
        ])
        return label
    }

    private func cleanupSubtitleView() {
        subtitleAttachWorkItem?.cancel()
        subtitleAttachWorkItem = nil
        subtitleAttachAttempts = 0
        subtitleView?.removeFromSuperview()
        subtitleView = nil
        activeWindow = nil
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipStartWorkItem?.cancel()
        pipStartWorkItem = nil
        pipStartAttempts = 0
        scheduleSubtitleAttach(after: 0.15)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        subtitleAttachAttempts = 0
        scheduleSubtitleAttach(after: 0.1)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        cleanupSubtitleView()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Logger.log("PlayerLayer PiP failed: \(error.localizedDescription)", level: .error)
        cleanupSubtitleView()
        if pipStartAttempts < 12 {
            schedulePiPStartAttempt(after: 0.4)
        }
    }

    private func scheduleSubtitleAttach(after delay: TimeInterval) {
        subtitleAttachWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attachSubtitleViewToPiPWindow()
        }
        subtitleAttachWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func attachSubtitleViewToPiPWindow() {
        guard pipController?.isPictureInPictureActive == true || pipStartAttempts == 0 else { return }
        guard let window = currentPiPWindow() else {
            subtitleAttachAttempts += 1
            if subtitleAttachAttempts < 20 {
                scheduleSubtitleAttach(after: 0.15)
            } else {
                Logger.log("Cannot find PiP window for PlayerLayer subtitle.", level: .error)
            }
            return
        }

        if activeWindow === window, let subtitleView {
            window.bringSubviewToFront(subtitleView)
            return
        }

        subtitleView?.removeFromSuperview()
        activeWindow = window
        subtitleView = makeSubtitleView(in: window)
        if let subtitleView {
            window.bringSubviewToFront(subtitleView)
        }
    }

    private func currentPiPWindow() -> UIWindow? {
        let windows = allApplicationWindows().filter { !$0.isHidden && $0.alpha > 0 }
        let appKeyWindow = currentKeyWindow()
        let sourceWindow = sourceView.window
        let candidates = windows.filter { window in
            if let sourceWindow, window === sourceWindow {
                return false
            }
            if let appKeyWindow, window === appKeyWindow {
                return false
            }
            return true
        }
        return candidates
            .sorted { scorePiPWindow($0) > scorePiPWindow($1) }
            .first
    }

    private func scorePiPWindow(_ window: UIWindow) -> Int {
        let className = String(describing: type(of: window)).lowercased()
        var score = Int(window.windowLevel.rawValue)
        if className.contains("picture") || className.contains("pip") {
            score += 300
        }
        if className.contains("av") || className.contains("pg") || className.contains("host") {
            score += 120
        }
        if !window.isKeyWindow {
            score += 40
        }
        if window.bounds.width < UIScreen.main.bounds.width || window.bounds.height < UIScreen.main.bounds.height {
            score += 30
        }
        return score
    }

    private func allApplicationWindows() -> [UIWindow] {
        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let legacyWindows = (UIApplication.shared.value(forKey: "windows") as? [UIWindow]) ?? []

        var uniqueWindows: [UIWindow] = []
        for window in sceneWindows + legacyWindows where !uniqueWindows.contains(where: { $0 === window }) {
            uniqueWindows.append(window)
        }
        return uniqueWindows
    }

    private func currentKeyWindow() -> UIWindow? {
        allApplicationWindows().first { $0.isKeyWindow }
    }
}

private final class PaddedSubtitleLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14) {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        let baseSize = super.intrinsicContentSize
        return CGSize(
            width: baseSize.width + contentInsets.left + contentInsets.right,
            height: baseSize.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: contentInsets)
        let textRect = super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
        return textRect.inset(by: UIEdgeInsets(
            top: -contentInsets.top,
            left: -contentInsets.left,
            bottom: -contentInsets.bottom,
            right: -contentInsets.right
        ))
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}
