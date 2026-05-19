import ReplayKit
import SwiftUI
import UIKit

extension Notification.Name {
    static let transifyrStartBroadcast = Notification.Name("transifyrStartBroadcast")
}

// Subclass tùy biến để can thiệp định dạng nút hệ thống ngay khi các subviews được nạp xong
class CustomBroadcastPickerView: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        // Tìm button hệ thống bên trong picker và gán icon/màu sắc trực tiếp
        if let button = subviews.compactMap({ $0 as? UIButton }).first {
            button.setImage(UIImage(systemName: "waveform.circle.fill"), for: .normal)
            button.tintColor = .white
            button.backgroundColor = .clear
            
            // Đảm bảo nút chiếm toàn bộ không gian để người dùng dễ chạm
            button.frame = bounds
        }
    }
}

struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = CustomBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.vteen.RealtimeTranslator.Broadcast"
        picker.showsMicrophoneButton = false

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
