import ReplayKit
import SwiftUI
import UIKit

extension Notification.Name {
    static let transifyrStartBroadcast = Notification.Name("transifyrStartBroadcast")
}

struct BroadcastPickerButton: View {
    var body: some View {
        ZStack {
            // Icon hiển thị custom bằng SwiftUI cực kỳ đẹp và sắc nét
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            
            // Nút gốc ẩn bằng cách set alpha rất nhỏ để vẫn bắt được sự kiện tap
            SystemBroadcastPickerRepresentable()
                .frame(width: 44, height: 44)
                .opacity(0.01) // Vẫn tương tác được nhưng không hiển thị giao diện mặc định
        }
    }
}

struct SystemBroadcastPickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
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
