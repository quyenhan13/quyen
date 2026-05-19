import ReplayKit
import SwiftUI
import UIKit

extension Notification.Name {
    static let transifyrStartBroadcast = Notification.Name("transifyrStartBroadcast")
}

struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.vteen.Transifyr.Broadcast"
        picker.showsMicrophoneButton = false

        // Chắc chắn tìm thấy button khi subviews của Apple được tạo
        DispatchQueue.main.async {
            if let button = self.findButton(in: picker) {
                button.setImage(UIImage(systemName: "waveform.circle.fill"), for: .normal)
                button.tintColor = .white
            }
        }

        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .transifyrStartBroadcast,
            object: nil,
            queue: .main
        ) { [weak picker] _ in
            guard let picker = picker else { return }
            if let button = self.findButton(in: picker) {
                button.sendActions(for: .touchUpInside)
            }
        }

        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func findButton(in view: UIView) -> UIButton? {
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

    final class Coordinator {
        var observer: NSObjectProtocol?

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
