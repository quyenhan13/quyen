import UIKit

final class FloatingTranslationOverlayManager: ObservableObject {
    static let shared = FloatingTranslationOverlayManager()

    @Published private(set) var isRunning = false

    private var window: UIWindow?
    private var controller: FloatingTranslationViewController?
    private var lastText = ""

    private init() {}

    func start() {
        guard window == nil else {
            isRunning = true
            return
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) else {
            Logger.log("Không tìm thấy UIWindowScene để tạo floating overlay.", level: .error)
            return
        }

        let controller = FloatingTranslationViewController()

        let overlayWindow = PassthroughOverlayWindow(windowScene: scene)
        overlayWindow.windowLevel = UIWindow.Level.statusBar + 1000
        overlayWindow.backgroundColor = .clear
        overlayWindow.rootViewController = controller
        overlayWindow.isHidden = false
        controller.loadViewIfNeeded()
        controller.updateText(lastText)

        self.controller = controller
        self.window = overlayWindow
        isRunning = true
    }

    func stop() {
        window?.isHidden = true
        window = nil
        controller = nil
        isRunning = false
    }

    func update(text: String, translation: String) {
        let next = (translation.isEmpty ? text : translation)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lastText = next
        controller?.updateText(next)
    }
}

private final class PassthroughOverlayWindow: UIWindow {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let root = rootViewController?.view,
              let hitView = root.hitTest(point, with: event) else { return false }
        return hitView !== root
    }
}

private final class FloatingTranslationViewController: UIViewController {
    private let label = UILabel()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private var hideTimer: Timer?
    private var panStartCenter = CGPoint.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        blurView.layer.cornerRadius = 18
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.alpha = 0
        blurView.isUserInteractionEnabled = true
        view.addSubview(blurView)

        label.textColor = .white
        label.font = .systemFont(ofSize: 20, weight: .heavy)
        label.numberOfLines = 1
        label.textAlignment = .left
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.95
        label.layer.shadowRadius = 4
        label.layer.shadowOffset = CGSize(width: 0, height: 2)
        label.alpha = 0
        blurView.contentView.addSubview(label)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        blurView.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if blurView.frame == .zero {
            blurView.frame = CGRect(x: -18, y: view.bounds.height * 0.48, width: 220, height: 56)
            label.frame = blurView.bounds.insetBy(dx: 18, dy: 8)
        }
    }

    func updateText(_ text: String) {
        guard isViewLoaded else { return }

        label.text = text
        hideTimer?.invalidate()

        guard !text.isEmpty else {
            setVisible(false)
            return
        }

        let width = min(max(textSize(text).width + 48, 120), min(view.bounds.width * 0.72, 360))
        var frame = blurView.frame
        frame.size = CGSize(width: width, height: 56)
        frame.origin.x = frame.midX < view.bounds.midX ? -18 : view.bounds.width - width + 18
        blurView.frame = frame
        label.frame = blurView.bounds.insetBy(dx: 18, dy: 8)

        setVisible(true)
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.setVisible(false)
        }
    }

    private func textSize(_ text: String) -> CGSize {
        (text as NSString).size(withAttributes: [.font: label.font as Any])
    }

    private func setVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.22) {
            self.blurView.alpha = visible ? 1 : 0
            self.label.alpha = visible ? 1 : 0
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            panStartCenter = blurView.center
        case .changed:
            let translation = recognizer.translation(in: view)
            blurView.center = CGPoint(x: panStartCenter.x + translation.x, y: panStartCenter.y + translation.y)
        case .ended, .cancelled:
            dockToNearestEdge()
        default:
            break
        }
    }

    private func dockToNearestEdge() {
        let margin: CGFloat = 18
        var frame = blurView.frame
        frame.origin.x = blurView.center.x < view.bounds.midX ? -margin : view.bounds.width - frame.width + margin
        frame.origin.y = min(max(frame.origin.y, view.safeAreaInsets.top + 20), view.bounds.height - frame.height - view.safeAreaInsets.bottom - 20)

        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4) {
            self.blurView.frame = frame
        }
    }
}
