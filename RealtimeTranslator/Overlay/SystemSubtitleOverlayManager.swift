import AVFoundation
import AVKit
import CoreMedia
import UIKit

final class SystemSubtitleOverlayManager: NSObject, ObservableObject {
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
    private let floatingScene = SystemFloatingSceneManager.shared

    override init() {
        super.init()
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

        guard isSupported, pipController?.isPictureInPictureActive != true else { return }
        do {
            try AudioSessionManager.configureForPlaybackOverlay()
            wantsPipStart = true
            acceptsUpdates = true
            
            DispatchQueue.main.async {
                self.isRunning = true
            }
            
            // Enqueue sample buffer lập tức để kích hoạt khả năng bắt đầu PiP
            enqueueFrame(force: true)
            startFrameTimer()
            
            // Thử khởi chạy PiP ngay lập tức
            if pipController?.isPictureInPicturePossible == true {
                pipController?.startPictureInPicture()
            }
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
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let fontSize: CGFloat = renderSize.width > 500 ? 32 : 24
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
            .strokeColor: UIColor.black,
            .strokeWidth: NSNumber(value: -3.5) // Viền đen thanh lịch giúp tăng độ tương phản rõ nét trên mọi nền video
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
        let boxWidth = textWidth + 40 < renderSize.width - 20 ? textWidth + 40 : renderSize.width - 20
        let boxHeight = textHeight + 20 < renderSize.height - 16 ? textHeight + 20 : renderSize.height - 16
        let boxRect = CGRect(
            x: (renderSize.width - boxWidth) / 2,
            y: (renderSize.height - boxHeight) / 2,
            width: boxWidth,
            height: boxHeight
        )

        // Vẽ nền hộp đen mờ (opacity 82% sang xịn)
        UIColor.black.withAlphaComponent(0.82).setFill()
        let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 16)
        path.fill()

        // Vẽ viền sáng tinh tế cho hộp phụ đề
        UIColor.white.withAlphaComponent(0.08).setStroke()
        let border = UIBezierPath(roundedRect: boxRect.insetBy(dx: 1, dy: 1), cornerRadius: 15)
        border.lineWidth = 1
        border.stroke()

        // Vẽ chữ căn giữa trong hộp
        let textRect = CGRect(
            x: boxRect.minX + 20,
            y: boxRect.minY + (boxRect.height - textHeight) / 2,
            width: boxRect.width - 40,
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
