import ReplayKit
import SwiftUI
import UIKit

extension Notification.Name {
    static let transifyrStartBroadcast = Notification.Name("transifyrStartBroadcast")
    static let transifyrBroadcastButtonTapped = Notification.Name("transifyrBroadcastButtonTapped")
}

final class CustomBroadcastPickerView: RPSystemBroadcastPickerView {
    var onButtonFound: ((UIButton) -> Void)?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if let button = findButton(in: self) {
            button.frame = bounds
            onButtonFound?(button)
        }
    }
    
    func findButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton {
            return button
        }
        for subview in view.subviews {
            if let found = findButton(in: subview) {
                return found
            }
        }
        return nil
    }
}

struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> CustomBroadcastPickerView {
        let picker = CustomBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.vteen.Transifyr.Broadcast"
        picker.showsMicrophoneButton = false

        picker.onButtonFound = { button in
            context.coordinator.button = button
            // Làm trong suốt hoàn toàn ảnh mặc định của Apple để không bị đè lên UI chính
            button.setImage(nil, for: .normal)
            button.tintColor = .clear
            
            button.removeTarget(nil, action: nil, for: .allEvents)
            button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .touchUpInside)
        }

        let coordinator = context.coordinator
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .transifyrStartBroadcast,
            object: nil,
            queue: .main
        ) { [weak picker] _ in
            guard let picker = picker else { return }
            if let button = coordinator.button {
                button.sendActions(for: .touchUpInside)
                Logger.log("Kich hoat thanh cong ReplayKit Broadcast Button.")
            } else if let button = picker.findButton(in: picker) {
                button.sendActions(for: .touchUpInside)
                Logger.log("Kich hoat thanh cong ReplayKit Broadcast Button (fallback search).")
            } else {
                Logger.log("Khong tim thay Apple ReplayKit button trong picker view.", level: .error)
            }
        }

        return picker
    }

    func updateUIView(_ uiView: CustomBroadcastPickerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var observer: NSObjectProtocol?
        var button: UIButton?

        @objc func buttonTapped() {
            Logger.log("Nguoi dung da tap vat ly vao ReplayKit Broadcast Button.")
            NotificationCenter.default.post(name: .transifyrBroadcastButtonTapped, object: nil)
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
