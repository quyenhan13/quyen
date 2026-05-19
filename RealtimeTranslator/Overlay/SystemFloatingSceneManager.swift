import Combine
import UIKit

final class SystemFloatingSceneManager: ObservableObject {
    static let shared = SystemFloatingSceneManager()

    @Published private(set) var isRunning = false

    private var window: UIWindow?
    private var controller: SystemFloatingSubtitleViewController?
    private var lastOriginal = ""
    private var lastTranslation = ""
    private var lastFailureReason = ""
    private let enableKey = "enable_system_floating_scene"

    private init() {}

    var isSupported: Bool {
        systemSceneEnabled
            && UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
    }

    private var systemSceneEnabled: Bool {
        UserDefaults.standard.object(forKey: enableKey) as? Bool ?? true
    }

    var diagnosticSummary: String {
        [
            "windowScene": UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene },
            "lastFailure": !lastFailureReason.isEmpty
        ]
        .map { "\($0.key)=\($0.value ? "yes" : "no")" }
        .sorted()
        .joined(separator: ", ")
    }

    @discardableResult
    func start() -> Bool {
        guard window == nil else {
            isRunning = true
            return true
        }

        guard isSupported else {
            lastFailureReason = "System floating scene is disabled or unavailable."
            Logger.log("System floating scene unavailable: \(diagnosticSummary)")
            return false
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) else {
            lastFailureReason = "No active UIWindowScene."
            Logger.log("System floating scene unavailable: \(lastFailureReason)")
            return false
        }

        let controller = SystemFloatingSubtitleViewController()
        let overlayWindow = makeRootSceneWindow(scene: scene)
        overlayWindow.windowLevel = UIWindow.Level.statusBar + 10000
        overlayWindow.backgroundColor = .clear
        overlayWindow.rootViewController = controller
        overlayWindow.isHidden = false
        overlayWindow.makeKeyAndVisible()

        controller.loadViewIfNeeded()
        controller.update(original: lastOriginal, translation: lastTranslation)

        self.controller = controller
        self.window = overlayWindow
        isRunning = true
        Logger.log("System floating scene started: \(diagnosticSummary)")
        return true
    }

    func stop() {
        window?.isHidden = true
        window = nil
        controller = nil
        isRunning = false
    }

    func update(text: String, translation: String) {
        lastOriginal = text
        lastTranslation = translation
        controller?.update(original: text, translation: translation)
    }

    private func makeRootSceneWindow(scene: UIWindowScene) -> UIWindow {
        return PassthroughSystemWindow(windowScene: scene)
    }

}

private final class PassthroughSystemWindow: UIWindow {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let root = rootViewController?.view,
              let hitView = root.hitTest(point, with: event) else { return false }
        return hitView !== root
    }
}

private final class SystemFloatingSubtitleViewController: UIViewController {
    private let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let label = UILabel()
    private var hideTimer: Timer?
    private var panStartCenter = CGPoint.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.alpha = 0
        container.isUserInteractionEnabled = true
        view.addSubview(container)

        label.textColor = .white
        label.font = .systemFont(ofSize: 19, weight: .heavy)
        label.numberOfLines = 2
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.9
        label.layer.shadowRadius = 4
        label.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.contentView.addSubview(label)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        container.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if container.frame == .zero {
            let width = min(view.bounds.width - 36, 430)
            container.frame = CGRect(
                x: (view.bounds.width - width) / 2,
                y: view.bounds.height - view.safeAreaInsets.bottom - 128,
                width: width,
                height: 72
            )
        }
        label.frame = container.bounds.insetBy(dx: 18, dy: 10)
    }

    func update(original: String, translation: String) {
        let text = translation

        label.text = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        hideTimer?.invalidate()
        guard label.text?.isEmpty == false else {
            setVisible(false)
            return
        }

        setVisible(true)
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.setVisible(false)
        }
    }

    private func setVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.container.alpha = visible ? 1 : 0
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            panStartCenter = container.center
        case .changed:
            let translation = recognizer.translation(in: view)
            container.center = CGPoint(x: panStartCenter.x + translation.x, y: panStartCenter.y + translation.y)
        case .ended, .cancelled:
            clampToScreen()
        default:
            break
        }
    }

    private func clampToScreen() {
        var frame = container.frame
        frame.origin.x = min(max(frame.origin.x, 12), view.bounds.width - frame.width - 12)
        frame.origin.y = min(max(frame.origin.y, view.safeAreaInsets.top + 12), view.bounds.height - view.safeAreaInsets.bottom - frame.height - 12)

        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.3) {
            self.container.frame = frame
        }
    }
}
