import SwiftUI
import AVFoundation
import UIKit

struct HomeView: View {
    @ObservedObject var settings = AppSettings.shared
    @StateObject private var autoUpdateManager = AutoUpdateManager.shared
    @StateObject private var subtitleManager = SubtitleManager()
    @StateObject private var systemOverlay = SystemSubtitleOverlayManager()

    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                TransifyrBackground()

                VStack(spacing: 14) {
                    header
                    
                    // Live Preview của phụ đề nổi (Bắt buộc phải hiển thị để iOS cho phép PiP hoạt động mượt mà)
                    SystemOverlayLayerView(displayLayer: systemOverlay.displayLayer)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                        .opacity(systemOverlay.isRunning ? 1.0 : 0.01)

                    tabBar
                    listenPanel
                    broadcastPanel
                    consolePanel
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
            .navigationBarHidden(true)
        }
        .accentColor(.white)
        .onAppear {
            _ = settings.syncSharedSettings()
            subtitleManager.resetSharedSubtitleCache()
            subtitleManager.startBroadcastSubtitleSync()
            Task {
                await autoUpdateManager.checkForUpdates(silent: true)
            }
        }

        .onDisappear {
            subtitleManager.stopBroadcastSubtitleSync()
        }
        .onChange(of: subtitleManager.currentTranslatedText) { newValue in
            if newValue.isEmpty && subtitleManager.currentText.isEmpty { return }
            systemOverlay.update(text: subtitleManager.currentText, translation: newValue)
        }
        .onChange(of: subtitleManager.currentText) { newValue in
            if newValue.isEmpty && subtitleManager.currentTranslatedText.isEmpty { return }
            systemOverlay.update(text: newValue, translation: subtitleManager.currentTranslatedText)
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .alert(item: $autoUpdateManager.availableUpdate) { update in
            Alert(
                title: Text("Có bản cập nhật mới"),
                message: Text("Tải \(update.title) để cài IPA mới nhất."),
                primaryButton: .default(Text("Tải ngay")) {
                    autoUpdateManager.install(update)
                },
                secondaryButton: .cancel(Text("Để sau")) {
                    autoUpdateManager.dismiss(update)
                }
            )
        }
    }

    private var listenPanel: some View {
        HStack(spacing: 14) {
            Button(action: startBroadcastMode) {
                HStack(spacing: 8) {
                    Image(systemName: systemOverlay.isRunning ? "stop.fill" : "record.circle.fill")
                    Text(systemOverlay.isRunning ? "Dừng dịch" : "Bắt đầu thu")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(systemOverlay.isRunning ? TransifyrTheme.dangerGradient : TransifyrTheme.accentGradient)
                .clipShape(Capsule())
                .shadow(color: (systemOverlay.isRunning ? Color.red : TransifyrTheme.accent).opacity(0.4), radius: 12, y: 6)
            }

            Button(action: startPiPOnly) {
                HStack(spacing: 8) {
                    Image(systemName: "pip.enter")
                    Text("PiP")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            Button(action: testOverlay) {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                    Text("Test phụ đề")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
        .frame(height: 100)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(TransifyrTheme.accentGradient)
                    .frame(width: 42, height: 42)
                    .shadow(color: TransifyrTheme.accent.opacity(0.45), radius: 12)
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Transifyr")
                        .font(.system(size: 22, weight: .black))
                    Text("Lite")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(TransifyrTheme.accentGradient)
                }
                Text("Realtime subtitle translator")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(TransifyrTheme.textSecondary)
                    .textCase(.uppercase)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(systemOverlay.isRunning ? Color.green : TransifyrTheme.textSecondary)
                    .frame(width: 8, height: 8)
                    .shadow(color: (systemOverlay.isRunning ? Color.green : TransifyrTheme.textSecondary).opacity(0.8), radius: 6)
                Text(systemOverlay.isRunning ? "Dịch nổi" : "Sẵn sàng")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(TransifyrTheme.input)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(TransifyrTheme.border, lineWidth: 1))
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(title: "Dịch thuật", icon: "message.fill", active: true) {}

            NavigationLink(destination: SettingsView()) {
                tabLabel(title: "Cài đặt", icon: "gearshape.fill", active: false)
            }

        }
        .padding(4)
        .background(TransifyrTheme.input.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TransifyrTheme.border, lineWidth: 1))
    }

    private var broadcastPanel: some View {
        HStack(spacing: 12) {
            BroadcastPickerButton()
                .frame(width: 44, height: 44)
                .background(TransifyrTheme.input)
                .clipShape(Circle())
                .overlay(Circle().stroke(TransifyrTheme.borderLight, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text("Bắt âm thanh app khác")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Bật Transifyr Audio trong Broadcast để dịch như desktop")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(TransifyrTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: toggleFloatingOverlay) {
                Image(systemName: systemOverlay.isRunning ? "rectangle.slash" : "text.bubble.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(systemOverlay.isRunning ? TransifyrTheme.dangerGradient : TransifyrTheme.accentGradient)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
            }

            Button(action: openFrontBoardShell) {
                Image(systemName: "rectangle.on.rectangle.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(TransifyrTheme.borderLight, lineWidth: 1))
            }
        }
        .padding(12)
        .background(TransifyrTheme.input.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(TransifyrTheme.border, lineWidth: 1))
    }

    private var consolePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Xem trước phụ đề")
                    .font(.caption.weight(.bold))
                    .foregroundColor(TransifyrTheme.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Button(action: subtitleManager.clear) {
                    Text("Xóa log")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(TransifyrTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(TransifyrTheme.input)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("[Hệ thống] Transifyr Lite sẵn sàng hoạt động.")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(TransifyrTheme.accentLight)

                        ForEach(subtitleManager.historyLines) { line in
                            logBlock(original: line.text, translated: line.textTranslated)
                        }

                        if !subtitleManager.currentText.isEmpty || !subtitleManager.currentTranslatedText.isEmpty {
                            logBlock(original: subtitleManager.currentText, translated: subtitleManager.currentTranslatedText, live: true)
                                .id("current")
                        }
                    }
                    .padding(14)
                }
                .background(Color.black.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                .onChange(of: subtitleManager.currentTranslatedText) { _ in
                    withAnimation { proxy.scrollTo("current", anchor: .bottom) }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .background(TransifyrTheme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TransifyrTheme.borderLight, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }

    private var footer: some View {
        Text("Phiên bản 1.0.0 • Soniox realtime • VTeen")
            .font(.caption2)
            .foregroundColor(TransifyrTheme.textMuted)
    }

    private func logBlock(original: String, translated: String, live: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !original.isEmpty {
                Text(original)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TransifyrTheme.textSecondary)
                    .padding(.leading, 8)
                    .overlay(Rectangle().fill(TransifyrTheme.accent.opacity(0.45)).frame(width: 2), alignment: .leading)
            }
            if !translated.isEmpty {
                Text(translated)
                    .font(.system(size: live ? 19 : 17, weight: .bold))
                    .foregroundColor(.cyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }

    private func tabButton(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tabLabel(title: title, icon: icon, active: active)
        }
    }

    private func tabLabel(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundColor(active ? .white : TransifyrTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(active ? AnyShapeStyle(TransifyrTheme.accentGradient) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func toggleFloatingOverlay() {
        if systemOverlay.isRunning {
            subtitleManager.requestBroadcastStop()
            systemOverlay.stop()
        } else {
            systemOverlay.start()
        }
    }

    private func openFrontBoardShell() {
        guard let url = URL(string: "transifyr-frontboard://show") else { return }
        UIApplication.shared.open(url) { success in
            if !success {
                alertMessage = "Chua cai TransifyrFrontBoard.tipa hoac TrollStore chua cho mo shell."
                showAlert = true
            }
        }
    }

    private func testOverlay() {
        if !systemOverlay.isRunning {
            systemOverlay.start()
        }
        // Gửi nội dung test phụ đề ngay lập tức
        systemOverlay.update(
            text: "Hello! This is a real-time subtitle translation test overlay.",
            translation: "Xin chào! Đây là phụ đề dịch thuật thời gian thực thử nghiệm."
        )
    }

    private func startPiPOnly() {
        if systemOverlay.isRunning {
            systemOverlay.stop()
        }
        PlayerLayerPiPSubtitleManager.shared.update(translation: "Đang thử phụ đề nổi bằng PiP.")
        PlayerLayerPiPSubtitleManager.shared.start()
    }

    private func startBroadcastMode() {
        if systemOverlay.isRunning {
            subtitleManager.requestBroadcastStop()
            systemOverlay.stop()
            return
        }

        guard settings.syncSharedSettings() else {
            alertMessage = "Vui l\u{00F2}ng v\u{00E0}o C\u{00E0}i \u{0111}\u{1EB7}t v\u{00E0} l\u{01B0}u Soniox API Key tr\u{01B0}\u{1EDB}c khi b\u{1EAD}t Broadcast."
            showAlert = true
            return
        }

        guard systemOverlay.isSupported else {
            alertMessage = "May nay khong ho tro PiP overlay de hien ben ngoai app."
            showAlert = true
            return
        }

        _ = subtitleManager.beginBroadcastSession()
        systemOverlay.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .transifyrStartBroadcast, object: nil)
        }
    }
}

struct TransifyrBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.035, blue: 0.09)
            LinearGradient(
                colors: [
                    TransifyrTheme.accent.opacity(0.22),
                    Color(red: 0.85, green: 0.28, blue: 0.94).opacity(0.08),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }
}

enum TransifyrTheme {
    static let accent = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let accentLight = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let textSecondary = Color(red: 0.58, green: 0.64, blue: 0.72)
    static let textMuted = Color(red: 0.39, green: 0.45, blue: 0.55)
    static let glass = Color(red: 0.07, green: 0.065, blue: 0.14).opacity(0.78)
    static let input = Color.white.opacity(0.045)
    static let border = Color.white.opacity(0.06)
    static let borderLight = accent.opacity(0.22)

    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.86, green: 0.28, blue: 0.94)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let dangerGradient = LinearGradient(
        colors: [Color(red: 0.94, green: 0.27, blue: 0.27), Color(red: 0.95, green: 0.24, blue: 0.37)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct SystemOverlayLayerView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        
        displayLayer.frame = view.bounds
        view.layer.addSublayer(displayLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = uiView.bounds
        CATransaction.commit()
    }
}
