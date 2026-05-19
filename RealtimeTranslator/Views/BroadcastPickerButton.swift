import ReplayKit
import SwiftUI
import UIKit

extension Notification.Name {
    static let transifyrStartBroadcast = Notification.Name("transifyrStartBroadcast")
}

struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.vteen.RealtimeTranslator.Broadcast"
        picker.showsMicrophoneButton = false

        if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
            button.setImage(UIImage(systemName: "waveform.circle.fill"), for: .normal)
            button.tintColor = .white
        }

        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .transifyrStartBroadcast,
            object: nil,
            queue: .main
        ) { [weak picker] _ in
            picker?.subviews
                .compactMap { $0 as? UIButton }
                .first?
                .sendActions(for: .touchUpInside)
        }

        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
