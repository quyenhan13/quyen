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
                    tabBar
                    listenPanel
                    broadcastPanel
                    consolePanel
                    
                    // Live Preview của phụ đề nổi (Bắt buộc phải hiển thị để iOS cho phép PiP hoạt động mượt mà)
                    SystemOverlayLayerView(displayLayer: systemOverlay.displayLayer)
                        .frame(height: systemOverlay.isRunning ? 120 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .padding(.bottom, systemOverlay.isRunning ? 10 : 0)
                        .allowsHitTesting(false)
                        .opacity(systemOverlay.isRunning ? 1.0 : 0.01)

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
        HStack(spacing: 12) {
            Button(action: startBroadcastMode) {
                HStack(spacing: 8) {
                    Image(systemName: systemOverlay.isRunning ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(systemOverlay.isRunning ? "DỪNG DỊCH" : "BẮT ĐẦU THU")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(systemOverlay.isRunning ? TransifyrTheme.dangerGradient : TransifyrTheme.accentGradient)
                )
                .shadow(color: (systemOverlay.isRunning ? Color.red : TransifyrTheme.accent).opacity(0.35), radius: 12, x: 0, y: 6)
            }

            Button(action: startPiPOnly) {
                VStack(spacing: 4) {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 18, weight: .bold))
                    Text("PiP")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 58, height: 52)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            Button(action: testOverlay) {
                VStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Test")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 58, height: 52)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
        .frame(height: 80)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(TransifyrTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .shadow(color: TransifyrTheme.accent.opacity(0.4), radius: 12, y: 4)
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Transifyr")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Lite")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(TransifyrTheme.accentGradient)
                }
                Text("Realtime subtitle translator")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(TransifyrTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(systemOverlay.isRunning ? Color(red: 0.0, green: 0.9, blue: 0.4) : TransifyrTheme.textSecondary)
                    .frame(width: 8, height: 8)
                    .shadow(color: (systemOverlay.isRunning ? Color(red: 0.0, green: 0.9, blue: 0.4) : TransifyrTheme.textSecondary).opacity(0.8), radius: 6)
                Text(systemOverlay.isRunning ? "DỊCH NỔI" : "SẴN SÀNG")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
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
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var broadcastPanel: some View {
        HStack(spacing: 12) {
            BroadcastPickerButton()
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text("Bắt âm thanh app khác")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Bật Transifyr Audio trong Broadcast để dịch như desktop")
                    .font(.system(size: 11, weight: .medium))
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
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
        .padding(12)
        .glassCardStyle()
    }

    private var consolePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TransifyrTheme.accent)
                        .frame(width: 6, height: 6)
                    Text("Xem trước phụ đề")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TransifyrTheme.textSecondary)
                }
                Spacer()
                Button(action: subtitleManager.clear) {
                    Text("Xóa log")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("[Hệ thống] Transifyr Lite sẵn sàng hoạt động.")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(TransifyrTheme.accentLight)
                            .padding(.bottom, 4)

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
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
                .onChange(of: subtitleManager.currentTranslatedText) { _ in
                    withAnimation { proxy.scrollTo("current", anchor: .bottom) }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .glassCardStyle()
    }

    private var footer: some View {
        Text("Phiên bản 1.0.0 • Soniox realtime • VTeen")
            .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: live ? 19 : 17, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.0, green: 0.85, blue: 0.95))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
        .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .bottom)
    }

    private func tabButton(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tabLabel(title: title, icon: icon, active: active)
        }
    }

    private func tabLabel(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(active ? .white : TransifyrTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(active ? AnyShapeStyle(TransifyrTheme.accentGradient) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 11))
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
            alertMessage = "Vui lòng vào Cài đặt và lưu Soniox API Key trước khi bật Broadcast."
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
            Color(red: 0.03, green: 0.025, blue: 0.07)
            
            // Premium Glowing Mesh circles
            Circle()
                .fill(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.18))
                .frame(width: 380, height: 380)
                .blur(radius: 80)
                .offset(x: -120, y: -220)
            
            Circle()
                .fill(Color(red: 0.86, green: 0.28, blue: 0.94).opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 140, y: 160)
            
            Circle()
                .fill(Color(red: 0.0, green: 0.8, blue: 0.95).opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: -140, y: 280)
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

// Premium visual modifiers for premium designs
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.06, green: 0.05, blue: 0.12).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.02), TransifyrTheme.accent.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: 15, x: 0, y: 8)
    }
}

extension View {
    func glassCardStyle() -> some View {
        self.modifier(GlassCardModifier())
    }
}
