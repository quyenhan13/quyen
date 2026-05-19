import AVFoundation
import AVKit
import CoreMedia
import UIKit

final class SystemSubtitleOverlayManager: NSObject, ObservableObject {
    static var shared: SystemSubtitleOverlayManager?
    @Published var isRunning = false
    @Published var isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var frameTimer: Timer?
    private var currentText = ""
    private var lastRenderSize = CGSize.zero
    private var hideTextAt: Date?
    private var frameIndex: Int64 = 0
    private let frameRate: Int32 = 24
    private var wantsPipStart = false
    private var acceptsUpdates = false
    private var pipStartAttempts = 0
    private var pipStartWorkItem: DispatchWorkItem?
    private let floatingScene = SystemFloatingSceneManager.shared

    override init() {
        super.init()
        SystemSubtitleOverlayManager.shared = self
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.clear.cgColor

        if #available(iOS 15.0, *) {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: source)
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.delegate = self
            controller.setValue(1, forKey: "controlsStyle")
            controller.setValue(true, forKey: "requiresLinearPlayback")
            pipController = controller
        }
    }

    func start() {
        if floatingScene.start() {
            acceptsUpdates = true
            DispatchQueue.main.async {
                self.isRunning = true
            }
            return
        }

        startPiPFallback()
    }

    func startPiPOnly() {
        startPiPFallback()
    }

    private func startPiPFallback() {
        guard isSupported, pipController?.isPictureInPictureActive != true else { return }
        do {
            try AudioSessionManager.configureForPlaybackOverlay()
            wantsPipStart = true
            acceptsUpdates = true
            pipStartAttempts = 0

            DispatchQueue.main.async {
                self.isRunning = true
            }

            enqueueFrame(force: true)
            startFrameTimer()
            schedulePiPStartAttempt(after: 0.15)
        } catch {
            Logger.log("Không thể bật phụ đề nổi: \(error.localizedDescription)", level: .error)
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func stop() {
        wantsPipStart = false
        acceptsUpdates = false
        pipStartWorkItem?.cancel()
        pipStartWorkItem = nil
        pipStartAttempts = 0
        hideTextAt = nil
        currentText = ""
        floatingScene.update(text: "", translation: "")
        enqueueFrame(force: true)
        displayLayer.flushAndRemoveImage()
        floatingScene.stop()
        frameTimer?.invalidate()
        frameTimer = nil
        pipController?.stopPictureInPicture()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    func update(text: String, translation: String) {
        guard acceptsUpdates || floatingScene.isRunning || pipController?.isPictureInPictureActive == true else { return }
        currentText = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        hideTextAt = currentText.isEmpty ? nil : Date().addingTimeInterval(6)
        floatingScene.update(text: "", translation: translation)
        enqueueFrame(force: true)
    }

    private func startFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(frameRate), repeats: true) { [weak self] _ in
            self?.enqueueFrame(force: false)
        }
        frameTimer?.tolerance = 0.01
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
        guard wantsPipStart, pipController?.isPictureInPictureActive != true else { return }
        enqueueFrame(force: true)

        if pipController?.isPictureInPicturePossible == true {
            Logger.log("PiP possible, starting picture-in-picture.")
            pipController?.startPictureInPicture()
            return
        }

        pipStartAttempts += 1
        guard pipStartAttempts < 12 else {
            Logger.log("PiP not possible after \(pipStartAttempts) attempts.", level: .error)
            return
        }

        Logger.log("PiP not possible yet, retry \(pipStartAttempts).")
        schedulePiPStartAttempt(after: 0.25)
    }

    private func enqueueFrame(force: Bool) {
        guard force || pipController?.isPictureInPictureActive == true else { return }
        if let hideTextAt, Date() >= hideTextAt {
            currentText = ""
            self.hideTextAt = nil
        }
        guard let buffer = makeSampleBuffer(text: currentText) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(buffer)
    }

    private func makeSampleBuffer(text: String) -> CMSampleBuffer? {
        guard let pixelBuffer = makePixelBuffer(text: text) else { return nil }

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        let pts = CMTime(value: frameIndex, timescale: frameRate)
        frameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: frameRate),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        if let sampleBuffer,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [CFMutableDictionary] {
            for item in attachments {
                CFDictionarySetValue(
                    item,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            }
        }
        return sampleBuffer
    }

    private func makePixelBuffer(text: String) -> CVPixelBuffer? {
        let renderSize = currentRenderSize()
        if renderSize != lastRenderSize {
            lastRenderSize = renderSize
        }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width),
            Int(renderSize.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        guard let context = CGContext(
            data: baseAddress,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        UIGraphicsPushContext(context)
        UIColor.clear.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: renderSize)).fill()

        let displayText = compactSubtitle(text)
        guard !displayText.isEmpty else {
            UIGraphicsPopContext()
            return pixelBuffer
        }

        // Cấu hình Paragraph Style cho phụ đề tĩnh căn giữa và tự động xuống dòng
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let textShadow = NSShadow()
        textShadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
        textShadow.shadowOffset = CGSize(width: 0, height: 1.5)
        textShadow.shadowBlurRadius = 3.0
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let fontSize: CGFloat = renderSize.width > 500 ? 30 : 22
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0),
            .paragraphStyle: paragraph,
            .strokeColor: UIColor.black.withAlphaComponent(0.85),
            .strokeWidth: NSNumber(value: -2.0),
            .shadow: textShadow
        ]

        let nsText = NSString(string: displayText)
        let maxTextWidth = renderSize.width - 60
        let boundingBox = nsText.boundingRect(
            with: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttrs,
            context: nil
        )

        let textWidth = CGFloat(ceil(Double(boundingBox.width)))
        let textHeight = CGFloat(ceil(Double(boundingBox.height)))

        // Hộp đen mờ bo tròn ôm sát nội dung chữ (Padding ngang 40, dọc 20) - Dùng toán tử ba ngôi loại bỏ hoàn toàn cảnh báo/lỗi phân giải kiểu dữ liệu
        let boxWidth = textWidth + 44 < renderSize.width - 20 ? textWidth + 44 : renderSize.width - 20
        let boxHeight = textHeight + 22 < renderSize.height - 16 ? textHeight + 22 : renderSize.height - 16
        let boxRect = CGRect(
            x: (renderSize.width - boxWidth) / 2,
            y: (renderSize.height - boxHeight) / 2,
            width: boxWidth,
            height: boxHeight
        )

        // Vẽ nền hộp đen mờ (opacity 82% sang xịn)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 0.82).cgColor,
            UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 0.88).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.saveGState()
            let clipPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 16)
            clipPath.addClip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: boxRect.midX, y: boxRect.minY),
                end: CGPoint(x: boxRect.midX, y: boxRect.maxY),
                options: []
            )
            context.restoreGState()
        }
        UIColor.clear.setFill()
        let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 16)
        path.fill()

        // Vẽ viền sáng tinh tế cho hộp phụ đề
        UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12).setStroke()
        let border = UIBezierPath(roundedRect: boxRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 16)
        border.lineWidth = 1
        border.stroke()

        // Vẽ thêm viền vàng ấm áp siêu mảnh ở vòng trong tạo độ tương tương phản và chiều sâu 3D đẳng cấp
        UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.12).setStroke()
        let innerHighlight = UIBezierPath(roundedRect: boxRect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 15)
        innerHighlight.lineWidth = 0.5
        innerHighlight.stroke()

        // Vẽ chữ căn giữa trong hộp
        let textRect = CGRect(
            x: boxRect.minX + 22,
            y: boxRect.minY + (boxRect.height - textHeight) / 2,
            width: boxRect.width - 44,
            height: textHeight
        )

        context.saveGState()
        nsText.draw(in: textRect, withAttributes: textAttrs)
        context.restoreGState()

        UIGraphicsPopContext()
        return pixelBuffer
    }

    private func compactSubtitle(_ text: String, limit: Int = 220) -> String {
        let normalized = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.suffix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentRenderSize() -> CGSize {
        let screenBounds = UIScreen.main.bounds
        let isLandscape = screenBounds.width > screenBounds.height
        // Thiết lập kích thước tỉ lệ vàng cho hộp phụ đề (aspect ratio rộng để ôm trọn 1-2 dòng)
        if isLandscape {
            return CGSize(width: 720, height: 140)
        } else {
            return CGSize(width: 480, height: 120)
        }
    }
}

extension SystemSubtitleOverlayManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipStartWorkItem?.cancel()
        pipStartWorkItem = nil
        pipStartAttempts = 0
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Logger.log("PiP failed to start: \(error.localizedDescription)", level: .error)
        if wantsPipStart, pipStartAttempts < 12 {
            schedulePiPStartAttempt(after: 0.4)
        }
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
}

extension SystemSubtitleOverlayManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(value: 24 * 60 * 60, timescale: 1))
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
