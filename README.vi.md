<p align="center">
  <img src="images/app-banner.png" alt="capcap app banner" width="760" />
</p>

<h1 align="center">capcap</h1>

<p align="center">
  Công cụ chụp màn hình trên thanh menu macOS: nhấn đúp <code>⌘</code> để chụp, chú thích, ghép ảnh dài, làm đẹp, ghim và tải lên.
</p>

<p align="center">
  <a href="https://github.com/realskyrin/capcap/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/realskyrin/capcap?style=flat-square"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.vi.md">Tiếng Việt</a>
</p>

<p align="center">
  <a href="https://github.com/realskyrin/capcap/releases/latest">Tải xuống</a> ·
  <a href="https://github.com/realskyrin/homebrew-tap">Homebrew</a> ·
  <a href="CHANGELOG.md">Nhật ký thay đổi</a> ·
  <a href="https://github.com/realskyrin/capcap/issues">Issues</a>
</p>

**Cách nhanh để chụp, đánh dấu và chia sẻ ảnh chụp màn hình trên macOS.** Nhấn đúp `⌘` ở bất kỳ đâu để chụp cửa sổ, kéo chọn vùng, ghép trang dài bằng cuộn, rồi chỉnh sửa trong một cửa sổ nổi. capcap nằm trên thanh menu, không có biểu tượng Dock, không đo lường từ xa, không đăng ký thuê bao và không có phụ thuộc bên thứ ba. Bạn có thể cấu hình dịch vụ lưu ảnh riêng để sao chép URL công khai chỉ với một lần bấm.

<p align="center">
  <img src="images/editor.png" alt="capcap annotation editor" width="760" />
</p>

## Vì sao chọn capcap

- **Một phím tắt, thao tác nhanh**: nhấn đúp `⌘` hoặc dùng phím tắt toàn cục tùy chỉnh.
- **Chụp cửa sổ hoặc vùng chính xác**: bấm vào cửa sổ được phát hiện, hoặc kéo chọn vùng với độ phân giải Retina.
- **Trình chỉnh sửa chú thích thật sự**: mũi tên, số thứ tự, chữ, mosaic, bút tô sáng và bút vẽ đều có thể chỉnh lại sau khi đặt.
- **Chụp dài**: cuộn trong vùng chọn, xem bản ghép trực tiếp, rồi tiếp tục chỉnh sửa ảnh đã ghép.
- **Làm đẹp và ghim**: thêm nền, bo góc, bóng, khoảng đệm, hoặc ghim ảnh nổi trên các cửa sổ khác.
- **Chỉnh ảnh từ Finder**: chọn một ảnh trong Finder và mở thẳng vào trình chỉnh sửa mà không sửa tệp gốc.
- **Lịch sử cục bộ**: sao chép lại nhanh ảnh chụp, màu đã chọn và liên kết tải lên từ thanh menu.
- **Tải lên dịch vụ ảnh riêng**: hỗ trợ Tencent COS, Qiniu Kodo và Aliyun OSS. Thông tin xác thực chỉ lưu trên Mac của bạn.
- **AppKit thuần**: không SwiftUI, không Electron, không đo lường từ xa.

## Xem trước

<table>
<tr>
  <td width="50%" align="center"><img src="images/window-snap.png" alt="Smart window detection" /><br/><sub><b>Chụp cửa sổ một lần bấm</b><br/>capcap tự phát hiện viền cửa sổ.</sub></td>
  <td width="50%" align="center"><img src="images/history.png" alt="Menu bar history" /><br/><sub><b>Lịch sử trên thanh menu</b><br/>Sao chép lại ảnh và màu gần đây.</sub></td>
</tr>
<tr>
  <td width="50%" align="center"><img src="images/scroll-stitch.png" alt="Scroll capture" /><br/><sub><b>Ghép trang dài</b><br/>Cuộn và xem kết quả ghép trực tiếp.</sub></td>
  <td width="50%" align="center"><img src="images/beautify.png" alt="Beautify mode" /><br/><sub><b>Làm đẹp một lần bấm</b><br/>Nền, bo góc, bóng và khoảng đệm đều có thể chỉnh.</sub></td>
</tr>
<tr>
  <td colspan="2" align="center"><img src="images/image-hosting.png" alt="Image host settings" width="520" /><br/><sub><b>Tải lên dịch vụ ảnh</b><br/>Tải ảnh hiện tại lên và sao chép URL công khai.</sub></td>
</tr>
</table>

## Yêu cầu

- macOS 14.0 trở lên
- Quyền Trợ năng cho thao tác nhấn đúp `⌘`
- Quyền Ghi màn hình cho ScreenCaptureKit
- Quyền Tự động hóa Finder khi chỉnh ảnh đã chọn

## Cài đặt bằng Homebrew

```bash
brew tap realskyrin/tap
brew install --cask realskyrin/tap/capcap
```

## Cảnh báo xác minh macOS

Nếu macOS hiện cảnh báo như `Apple không thể xác minh "capcap" không chứa phần mềm độc hại`, hãy gỡ cờ quarantine khỏi gói ứng dụng mà bạn tin cậy rồi mở lại:

```bash
xattr -dr com.apple.quarantine /Applications/capcap.app
```

Nếu bạn đang chạy bản tự biên dịch thay vì ứng dụng trong `/Applications`, hãy thay đường dẫn bằng vị trí thực tế, ví dụ:

```bash
xattr -dr com.apple.quarantine ./build/capcap.app
```

Chỉ chạy lệnh này với các bản build bạn tin cậy, chẳng hạn bản tải từ kho này hoặc bản bạn tự biên dịch.

## Biên dịch từ mã nguồn

```bash
./scripts/bundle.sh
```

Khi phát triển cục bộ:

```bash
bash scripts/rebuild-and-open.sh
```

## Cách dùng

1. Nhấn đúp `⌘ Command`, bấm phím tắt tùy chỉnh, hoặc chọn chụp màn hình từ thanh menu.
2. Bấm vào cửa sổ để chụp hoặc kéo chọn vùng bất kỳ.
3. Dùng thanh công cụ nổi để chú thích, lấy màu, chụp cuộn, làm đẹp, lưu, ghim, tải lên hoặc xác nhận.
4. Bấm dấu tích xanh hoặc `Enter` để sao chép kết quả. `Esc` hoặc `x` để hủy.

## Công cụ chỉnh sửa

| Công cụ | Chức năng |
| --- | --- |
| Hình chữ nhật / ellipse | Vẽ hình với màu và độ dày nét |
| Mũi tên | Vẽ mũi tên và chỉnh điểm cuối hoặc đường cong sau đó |
| Bút / bút tô sáng | Vẽ tự do hoặc đánh dấu trong suốt |
| Mosaic | Làm mờ vùng nhạy cảm bằng pixel |
| Số thứ tự / chữ | Thêm nhãn đánh số và văn bản có thể chỉnh |
| Lấy màu | Sao chép màu màn hình dạng `#RRGGBB` |
| Chụp cuộn / làm đẹp / ghim / tải lên | Hoàn thiện và chia sẻ ảnh |

## Cài đặt

Bạn có thể đổi ngôn ngữ, biểu tượng thanh menu, khởi chạy khi đăng nhập, phím tắt, kích thước lịch sử, dịch vụ tải ảnh và lối tắt quyền hệ thống. Lớp phủ vùng chọn và trình chỉnh sửa mặc định hiển thị trong bản ghi màn hình bên ngoài mà không cần thiết lập thêm. Giao diện hỗ trợ 简体中文, 繁體中文, English, 日本語, 한국어, Français, Русский và Tiếng Việt.

## Giấy phép

[MIT](LICENSE)
