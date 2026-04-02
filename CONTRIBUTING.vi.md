# Đóng góp cho react-native-media-toolkit

Đọc bản này bằng: [English](./CONTRIBUTING.md)

---

Cảm ơn bạn đã quan tâm đến việc đóng góp cho thư viện. Mọi đóng góp đều được chào đón: sửa lỗi, tính năng mới, cải thiện tài liệu, hoặc đặt câu hỏi.

Vui lòng đọc hướng dẫn này trước khi gửi bất cứ thứ gì.

---

## Quy tắc ứng xử

Dự án tuân theo quy tắc ứng xử chuẩn. Vui lòng lịch sự và xây dựng trong mọi tương tác.  
Xem chi tiết tại [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).

---

## Cấu trúc dự án

Đây là **Yarn monorepo** gồm 2 package:

- Thư mục gốc: thư viện (`react-native-media-toolkit`)
- `example/`: app demo (Expo Dev Client)

```
react-native-media-toolkit/        Source thư viện
├── src/                           TypeScript API và Nitro spec
├── ios/                           Triển khai native Swift
├── android/                       Triển khai native Kotlin
├── nitrogen/                      File bridge Nitro sinh tự động (không sửa thủ công)
└── example/                       App demo để test các thay đổi
```

---

## Yêu cầu môi trường

- Node.js: xem file `.nvmrc` để biết phiên bản chính xác
- Yarn 4+: `corepack enable && corepack prepare yarn@stable --activate`
- Phát triển iOS: Xcode 16.1+, CocoaPods
- Phát triển Android: Android Studio, JDK 17+

---

## Cài đặt môi trường

**1. Clone dự án**

```sh
git clone https://github.com/thangdevalone/react-native-media-toolkit.git
cd react-native-media-toolkit
```

**2. Cài dependencies**

```sh
yarn
```

Lệnh này cài dependencies cho cả thư viện và app demo.

**3. Cài pod cho iOS**

```sh
cd example/ios && pod install && cd ../..
```

---

## Chạy app demo

App demo dùng **Expo Dev Client**, cần build native trước khi chạy.

**Khởi động Metro**

```sh
yarn example start
```

**Chạy trên iOS**

```sh
yarn example ios
```

**Chạy trên Android**

```sh
yarn example android
```

Để xác nhận New Architecture đang hoạt động, tìm dòng sau trong Metro log:

```
Running "MediaToolkitExample" with {"fabric":true,"initialProps":{"concurrentRoot":true},"rootTag":1}
```

---

## Chỉnh sửa code native

**iOS (Swift):**  
Mở `example/ios/MediaToolkitExample.xcworkspace` trong Xcode.  
File source thư viện tại: `Pods > Development Pods > react-native-media-toolkit`.

**Android (Kotlin):**  
Mở `example/android` trong Android Studio.  
File source thư viện xuất hiện dưới `react-native-media-toolkit` trong cây dự án.

Sau khi thay đổi code native, phải build lại app — reload Metro là không đủ.

---

## Chạy codegen

Nếu thay đổi file spec Nitro (`src/MediaToolkit.nitro.ts`), cần sinh lại file bridge:

```sh
yarn codegen
```

Lệnh này chạy `nitrogen --config nitro.json` và cập nhật thư mục `nitrogen/`.  
Sau khi sinh lại, build lại app native để áp dụng thay đổi.

---

## Kiểm tra chất lượng code

**Kiểm tra TypeScript**

```sh
yarn typecheck
```

**Lint**

```sh
yarn lint
```

**Tự sửa lỗi lint**

```sh
yarn lint --fix
```

Tất cả các kiểm tra phải pass trước khi gửi pull request.

---

## Danh sách scripts

| Script | Mô tả |
|---|---|
| `yarn` | Cài tất cả dependencies |
| `yarn typecheck` | Kiểm tra TypeScript |
| `yarn lint` | Lint bằng ESLint |
| `yarn lint --fix` | Tự sửa lỗi lint |
| `yarn codegen` | Sinh lại file bridge Nitro |
| `yarn example start` | Khởi động Metro server |
| `yarn example ios` | Chạy example trên iOS |
| `yarn example android` | Chạy example trên Android |
| `yarn example build:ios` | Build iOS binary |
| `yarn example build:android` | Build Android APK |

---

## Gửi Pull Request

Trước khi mở pull request:

1. Mở issue trước nếu thay đổi lớn (tính năng mới, breaking change, hoặc thay đổi API).
2. Giữ PR nhỏ, tập trung vào một vấn đề duy nhất.
3. Đảm bảo `yarn typecheck` và `yarn lint` đều pass.
4. Test thay đổi trên cả iOS và Android bằng app demo.
5. Cập nhật `README.md` nếu thay đổi hoặc thêm API public.

**Định dạng tiêu đề PR:**

```
fix: sửa tọa độ crop cho video letterboxed
feat: thêm API getThumbnail
docs: cập nhật hướng dẫn cài đặt
```

---

## Báo lỗi

Khi báo lỗi, vui lòng cung cấp:

- Phiên bản thư viện (`react-native-media-toolkit@x.x.x`)
- Phiên bản React Native
- Nền tảng (phiên bản iOS / Android API level)
- Đoạn code tái hiện lỗi tối giản
- Thông báo lỗi hoặc stack trace đầy đủ

Gửi lỗi tại: [https://github.com/thangdevalone/react-native-media-toolkit/issues](https://github.com/thangdevalone/react-native-media-toolkit/issues)

---

## Giấy phép

Khi đóng góp, bạn đồng ý rằng đóng góp của mình sẽ được cấp phép theo [MIT License](./LICENSE).
