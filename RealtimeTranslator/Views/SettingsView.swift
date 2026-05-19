import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var apiKeyInput: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    let languages = [
        ("auto", "Tự động phát hiện"),
        ("en", "Tiếng Anh"),
        ("zh", "Tiếng Trung"),
        ("ja", "Tiếng Nhật"),
        ("ko", "Tiếng Hàn"),
        ("vi", "Tiếng Việt")
    ]

    let targetLanguages = [
        ("vi", "Tiếng Việt"),
        ("en", "Tiếng Anh")
    ]

    var body: some View {
        ZStack {
            TransifyrBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    translationCard
                    overlayCard
                    infoCard
                }
                .padding(18)
            }
        }
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { apiKeyInput = settings.apiKey }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cấu hình dịch thuật")
                .font(.system(size: 24, weight: .black))
                .foregroundColor(.white)
            Text("Thiết lập Soniox realtime, ngôn ngữ và phụ đề overlay.")
                .font(.subheadline)
                .foregroundColor(TransifyrTheme.textSecondary)
        }
    }

    private var translationCard: some View {
        settingsCard(title: "Dịch thuật", subtitle: "Máy chủ nhận dạng giọng nói và dịch thời gian thực.") {
            labeledPicker("Ngôn ngữ nguồn", selection: $settings.sourceLanguage, values: languages)
            labeledPicker("Dịch sang", selection: $settings.targetLanguage, values: targetLanguages)

            VStack(alignment: .leading, spacing: 7) {
                Text("Soniox API Key")
                    .formLabel()
                APIKeyTextView(text: $apiKeyInput)
                    .frame(height: 92)
                    .background(TransifyrTheme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TransifyrTheme.borderLight, lineWidth: 1))
                Text("Da nhap \(cleanAPIKey(apiKeyInput).count) ky tu")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(TransifyrTheme.textSecondary)
                Button(action: saveKey) {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Lưu API Key")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(TransifyrTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var overlayCard: some View {
        settingsCard(title: "Phụ đề Overlay", subtitle: "Chọn phong cách hiển thị khi xem phim trong trình duyệt.") {
            labeledPicker(
                "Style phụ đề",
                selection: $settings.overlayStyle,
                values: SubtitleStyle.allCases.map { ($0.rawValue, $0.rawValue) }
            )

            Toggle("Hiển thị câu gốc (dòng trực tiếp)", isOn: $settings.showOriginalSubtitle)
                .tint(TransifyrTheme.accent)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 6)
        }
    }

    private var infoCard: some View {
        settingsCard(title: "Thông tin", subtitle: "Cấu hình build hiện tại.") {
            infoRow("Model STT", "stt-rt-v4")
            infoRow("Endpoint", "transcribe-websocket")
            infoRow("Phiên bản", "1.0.0")
        }
    }

    private func settingsCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(TransifyrTheme.textSecondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TransifyrTheme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TransifyrTheme.borderLight, lineWidth: 1))
    }

    private func labeledPicker(_ title: String, selection: Binding<String>, values: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .formLabel()
            Picker(title, selection: selection) {
                ForEach(values, id: \.0) { value in
                    Text(value.1).tag(value.0)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(TransifyrTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TransifyrTheme.borderLight, lineWidth: 1))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(TransifyrTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func saveKey() {
        let cleanedKey = cleanAPIKey(apiKeyInput)
        guard !cleanedKey.isEmpty else {
            alertMessage = "API Key dang rong. Bam nut dan hoac dan lai key roi luu."
            showAlert = true
            return
        }

        apiKeyInput = cleanedKey
        let savedToKeychain = settings.saveAPIKey(cleanedKey)
        alertMessage = savedToKeychain
            ? "Đã lưu API Key thành công."
            : "Đã lưu API Key bằng chế độ TrollStore fallback."
        showAlert = true
    }

    private func cleanAPIKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct APIKeyTextView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .white
        view.tintColor = .white
        view.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardType = .asciiCapable
        view.returnKeyType = .done
        view.textContainerInset = UIEdgeInsets(top: 11, left: 8, bottom: 11, right: 8)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

private extension Text {
    func formLabel() -> some View {
        self.font(.caption.weight(.bold))
            .foregroundColor(TransifyrTheme.textSecondary)
            .textCase(.uppercase)
    }
}

struct TransifyrTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(TransifyrTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TransifyrTheme.borderLight, lineWidth: 1))
    }
}
