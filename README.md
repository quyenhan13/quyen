# RealtimeTranslator iOS - Ứng dụng Dịch Phim và Giọng Nói Thời Gian Thực

Ứng dụng iOS SwiftUI gọn nhẹ và cực mạnh dùng để thu âm, nhận diện giọng nói và dịch trực tiếp sang tiếng Việt thời gian thực thông qua Soniox Realtime Translation WebSocket API.

## ✨ Tính năng chính

- 🎙️ **Thu âm Microphone trực tiếp:** Nhận dạng và dịch trực tiếp từ loa ngoài hoặc các cuộc đối thoại thông thường.
- 🌐 **Tích hợp Web Browser:** Xem phim trên Youtube, Netflix, các web phim,... và phụ đề dịch hiển thị overlay ngay phía trên video.
- 🎨 **Phong cách phụ đề phong phú:** Cho phép tùy chỉnh cỡ chữ, viền chữ, neon style hay bento đẹp mắt.
- ⚙️ **Bảo mật tuyệt đối:** Lưu trữ API key bảo mật trong Apple Keychain.
- 🚀 **CI/CD Tự động:** Tự động sinh dự án qua XcodeGen và đóng gói thành file `.ipa` trực tiếp bằng GitHub Actions.

## 🛠️ Hướng dẫn xây dựng và cài đặt ứng dụng

### 1. Build tự động bằng GitHub Actions (Được khuyến khích)
1. Fork hoặc Push mã nguồn này lên một kho lưu trữ GitHub mới của bạn.
2. Vào tab **Actions** -> Chọn workflow **Build iOS IPA** -> Click **Run workflow**.
3. Sau khi kết thúc, tải file `RealtimeTranslator-unsigned-ipa` nằm trong mục Artifacts về máy tính của bạn.
4. Cài đặt file `.ipa` lên iPhone bằng các công cụ Sideload phổ biến như **Sideloadly**, **TrollStore**, **Feather**, hoặc **AltStore**.

### 2. Build thủ công trên máy Mac
Để xây dựng ứng dụng trực tiếp từ mã nguồn, bạn cần cài đặt **XcodeGen** trước:
```bash
# Cài đặt XcodeGen
brew install xcodegen

# Tạo file dự án .xcodeproj
xcodegen generate

# Mở dự án trong Xcode
open RealtimeTranslator.xcodeproj
```
Sau đó kết nối iPhone và nhấn **Run** trực tiếp từ Xcode.

## 📝 Sử dụng ứng dụng

1. Đăng ký một tài khoản miễn phí hoặc trả phí tại [Soniox](https://soniox.com) để lấy API Key.
2. Mở ứng dụng, vào mục **Cài đặt** và dán Soniox API Key của bạn vào rồi nhấn **Lưu**.
3. Chọn ngôn ngữ nguồn (ví dụ: English) và ngôn ngữ cần dịch sang (ví dụ: Tiếng Việt).
4. Nhấn **Bắt đầu dịch** và bắt đầu cuộc hội thoại hoặc xem phim để thưởng thức phụ đề dịch mượt mà!

---
*Phát triển bởi VTeen Team.*
