# react-native-media-toolkit

Đọc bản này bằng: [English](./README.md)

---

Thư viện xử lý ảnh và video native cho React Native — cắt ảnh, cắt video, nén, và trích xuất thumbnail.  
Xây dựng trên **Nitro Modules** (JSI), dùng `AVFoundation` trên iOS và **Jetpack Media3 Transformer** trên Android. Không phụ thuộc FFmpeg.

[![npm](https://img.shields.io/npm/v/react-native-media-toolkit)](https://www.npmjs.com/package/react-native-media-toolkit)
[![license](https://img.shields.io/npm/l/react-native-media-toolkit)](LICENSE)

---

## Tương thích

| Môi trường | Hỗ trợ |
|---|---|
| React Native CLI (New Architecture) | Có |
| Expo với Dev Client / Custom Build | Có |
| Expo Go | Không hỗ trợ (yêu cầu native build) |
| React Native | 0.75+ (bắt buộc New Architecture) |
| iOS | 15.1+ |
| Android | API 24+ (Android 7.0) |

> **Lưu ý Expo:** Thư viện yêu cầu native build. Không thể dùng với Expo Go.  
> Dùng `expo run:ios` hoặc `expo run:android` thay thế.

---

## Tính năng

| Tính năng | iOS | Android |
|---|---|---|
| Cắt ảnh | AVFoundation / CGImage | Bitmap |
| Nén ảnh | UIGraphicsImageRenderer | Bitmap |
| Cắt video theo thời gian (ms) | AVAssetExportSession | Media3 Transformer |
| Cắt vùng video (tương đối) | AVMutableVideoComposition | Media3 Presentation |
| Cắt thời gian + cắt vùng trong 1 lần encode | AVMutableVideoComposition | Media3 Transformer |
| Nén video | AVAssetExportSession presets | Media3 Transformer |
| Tắt âm thanh video | AVMutableComposition | Media3 Transformer |
| Lấy thumbnail từ video | AVAssetImageGenerator | MediaMetadataRetriever |

Mọi tọa độ crop dùng **hệ tương đối (0.0–1.0)** — không phụ thuộc độ phân giải màn hình.

---

## Cài đặt

```sh
npm install react-native-media-toolkit react-native-nitro-modules
# hoặc
yarn add react-native-media-toolkit react-native-nitro-modules
```

**iOS:**
```sh
cd ios && pod install
```

**Android:** Không cần bước thêm. Gradle tự xử lý Media3.

---

## Sử dụng

```typescript
import { MediaToolkit } from 'react-native-media-toolkit';
```

### Cắt ảnh

```typescript
const result = await MediaToolkit.cropImage(imageUri, {
  x: 0.25,      // offset trái so với chiều rộng ảnh (0.0–1.0)
  y: 0.25,      // offset trên so với chiều cao ảnh (0.0–1.0)
  width: 0.5,   // chiều rộng vùng cắt so với chiều rộng ảnh (0.0–1.0)
  height: 0.5,  // chiều cao vùng cắt so với chiều cao ảnh (0.0–1.0)
});
console.log(result.uri, result.width, result.height);
```

### Nén ảnh

```typescript
const result = await MediaToolkit.compressImage(imageUri, {
  quality: 70,       // 0–100, mặc định 80
  maxWidth: 1080,    // chiều rộng tối đa, giữ nguyên tỉ lệ
  format: 'jpeg',    // 'jpeg' | 'png' | 'webp'
});
```

### Cắt video theo thời gian

```typescript
const result = await MediaToolkit.trimVideo(videoUri, {
  startTime: 2000,  // thời điểm bắt đầu (milliseconds)
  endTime: 7000,    // thời điểm kết thúc (milliseconds)
});
```

### Cắt vùng video

```typescript
const result = await MediaToolkit.cropVideo(videoUri, {
  x: 0.1,
  y: 0.1,
  width: 0.8,
  height: 0.8,
});
```

### Cắt thời gian + cắt vùng trong 1 lần encode

```typescript
const result = await MediaToolkit.trimAndCropVideo(videoUri, {
  startTime: 1000,
  endTime: 8000,
  x: 0.0,
  y: 0.1,
  width: 1.0,
  height: 0.8,
});
```

> Nhanh hơn so với chạy trim và crop riêng lẻ — chỉ encode 1 lần duy nhất.

### Nén video

```typescript
const result = await MediaToolkit.compressVideo(videoUri, {
  quality: 'medium',  // 'low' | 'medium' | 'high'
  width: 1080,        // chiều rộng tối đa, giữ nguyên tỉ lệ
  bitrate: 2_000_000, // tuỳ chọn: ghi đè bitrate (bps)
});
```

### Tắt âm thanh video

```typescript
const result = await MediaToolkit.muteAudio(videoUri);
// Trả về file video mới với track âm thanh đã bị xoá
console.log(result.uri, result.duration);
```

> Hữu ích trong các luồng UGC cần strip audio trước khi upload.

### Lấy thumbnail từ video

```typescript
const thumb = await MediaToolkit.getThumbnail(videoUri, {
  timeMs: 3000,    // thời điểm lấy frame (milliseconds), mặc định 0
  quality: 85,     // 0–100, mặc định 80
  maxWidth: 720,   // chiều rộng output tối đa
});
console.log(thumb.uri, thumb.width, thumb.height);
```

---

## API Reference

### `cropImage(uri, options): Promise<MediaResult>`

| Option | Kiểu | Bắt buộc | Mô tả |
|---|---|---|---|
| `x` | number | Có | Offset trái (0.0–1.0) |
| `y` | number | Có | Offset trên (0.0–1.0) |
| `width` | number | Có | Chiều rộng vùng cắt (0.0–1.0) |
| `height` | number | Có | Chiều cao vùng cắt (0.0–1.0) |
| `outputPath` | string | Không | Đường dẫn tuyệt đối file output |

### `compressImage(uri, options): Promise<MediaResult>`

| Option | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `quality` | number | 80 | Chất lượng JPEG/WebP (0–100) |
| `maxWidth` | number | gốc | Chiều rộng tối đa output |
| `maxHeight` | number | gốc | Chiều cao tối đa output |
| `format` | string | `'jpeg'` | `'jpeg'` / `'png'` / `'webp'` |
| `outputPath` | string | — | Đường dẫn tuyệt đối file output |

### `trimVideo(uri, options): Promise<MediaResult>`

| Option | Kiểu | Bắt buộc | Mô tả |
|---|---|---|---|
| `startTime` | number | Có | Thời điểm bắt đầu (milliseconds) |
| `endTime` | number | Có | Thời điểm kết thúc (milliseconds) |
| `outputPath` | string | Không | Đường dẫn tuyệt đối file output |

### `cropVideo(uri, options): Promise<MediaResult>`

Cùng hệ toạ độ với `cropImage`. Tất cả giá trị là tương đối (0.0–1.0).

### `trimAndCropVideo(uri, options): Promise<MediaResult>`

Kết hợp trim và crop trong một lần encode duy nhất.

| Option | Kiểu | Bắt buộc | Mô tả |
|---|---|---|---|
| `startTime` | number | Có | Thời điểm bắt đầu (milliseconds) |
| `endTime` | number | Có | Thời điểm kết thúc (milliseconds) |
| `x` | number | Có | Offset trái vùng cắt (0.0–1.0) |
| `y` | number | Có | Offset trên vùng cắt (0.0–1.0) |
| `width` | number | Có | Chiều rộng vùng cắt (0.0–1.0) |
| `height` | number | Có | Chiều cao vùng cắt (0.0–1.0) |
| `outputPath` | string | Không | Đường dẫn tuyệt đối file output |

### `compressVideo(uri, options): Promise<MediaResult>`

| Option | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `quality` | string | `'medium'` | `'low'` / `'medium'` / `'high'` |
| `bitrate` | number | preset | Bitrate mục tiêu (bps) |
| `width` | number | gốc | Chiều rộng tối đa output |
| `outputPath` | string | — | Đường dẫn tuyệt đối file output |

### `muteAudio(uri, options?): Promise<MediaResult>`

Xoá track âm thanh khỏi video mà không re-encode luồng video.

| Option | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `outputPath` | string | — | Đường dẫn tuyệt đối file output |

### `getThumbnail(uri, options?): Promise<ThumbnailResult>`

| Option | Kiểu | Mặc định | Mô tả |
|---|---|---|---|
| `timeMs` | number | 0 | Thời điểm lấy frame (milliseconds) |
| `quality` | number | 80 | Chất lượng output (0–100) |
| `maxWidth` | number | gốc | Chiều rộng tối đa output |
| `outputPath` | string | — | Đường dẫn tuyệt đối file output |

### Kiểu trả về

```typescript
interface MediaResult {
  uri: string;      // file:// URI của file output
  size: number;     // kích thước file (bytes)
  width: number;    // chiều rộng output (pixels)
  height: number;   // chiều cao output (pixels)
  duration: number; // thời lượng (ms, bằng 0 với ảnh)
  mime: string;     // MIME type, ví dụ 'video/mp4'
}

interface ThumbnailResult {
  uri: string;    // file:// URI của file JPEG output
  size: number;   // kích thước file (bytes)
  width: number;  // chiều rộng output (pixels)
  height: number; // chiều cao output (pixels)
}
```

---

## UI tuỳ chỉnh

Thư viện này là **headless** — chỉ cung cấp logic xử lý native, không có UI đi kèm.  
Bạn hoàn toàn tự do xây dựng bất kỳ UI nào phù hợp với thiết kế ứng dụng: trim timeline, crop overlay, thanh tiến trình, v.v.

File `example/src/App.tsx` chứa các ví dụ tham khảo:
- `VideoTrimBar` — thanh timeline với 2 handle và dải thumbnail
- `CropOverlay` — khung cắt kéo được với 4 góc resize

Bạn có thể copy các component này vào project và tuỳ chỉnh theo nhu cầu.

---

## Hiệu năng

Thư viện được thiết kế theo hai nguyên tắc: tránh công việc không cần thiết và luôn ở trên native thread.

### Không có bridge overhead

Mọi lệnh gọi API đều qua **JSI (JavaScript Interface)** thông qua Nitro Modules. Không có JSON serialization giữa JS và native — đây là lời gọi hàm C++ trực tiếp. Điều này loại bỏ bottleneck chính của kiến trúc Bridge cũ.

### Trim không cần re-encode

`trimVideo` dùng `AVAssetExportPresetPassthrough` trên iOS và cắt theo keyframe trên Android. Bitstream được **copy nguyên vẹn** — không decode, không re-encode.

Tốc độ trim tỉ lệ thuận với **độ dài đoạn bạn cắt ra**, không phụ thuộc vào kích thước file gốc:

| Video gốc | Đoạn cắt | Thời gian (trim) | Thời gian (FFmpeg re-encode) |
|---|---|---|---|
| 2 phút · 1080p | 10 giây | ~0.3 giây | ~8 giây |
| 10 phút · 4K | 30 giây | ~0.8 giây | ~60 giây |
| 60 phút · 1080p | 60 giây | ~1.2 giây | ~5 phút |

Thậm chí cắt một đoạn từ video dài 60 phút cũng xong trong khoảng 1 giây — vì phần còn lại của file không bao giờ bị đụng vào.

### Trim + crop trong 1 lần encode

Nếu gọi `trimVideo` rồi `cropVideo` riêng lẻ = 2 lần encode đầy đủ: decode → encode → decode → encode. `trimAndCropVideo` thực hiện cả hai trong 1 session: decode → encode 1 lần duy nhất. Giảm một nửa thời gian xử lý và tránh mất chất lượng do encode 2 lần.

### So sánh với các thư viện phổ biến

| Thư viện | Engine native | JS bridge | Trim không re-encode | Trim+crop 1 lần |
|---|---|---|---|---|
| react-native-media-toolkit | AVFoundation / Media3 | JSI (không overhead) | Có | Có |
| react-native-video-trim | AVFoundation / FFmpegKit | Bridge | Chỉ iOS | Không |
| react-native-compressor | AVFoundation / MediaCodec | Bridge | Không | Không |
| ffmpeg-kit-react-native | FFmpeg (software) | Bridge | Không | Không |

Lưu ý: FFmpegKit là lựa chọn linh hoạt nhất cho các pipeline phức tạp. Thư viện này được tối ưu cho các tác vụ phổ biến: trim, crop, compress, và lấy thumbnail.

---

## Kiến trúc

```
react-native-media-toolkit/
├── src/
│   ├── MediaToolkit.nitro.ts   Nitro HybridObject spec + TypeScript types
│   └── index.ts                Public JS/TS API
├── ios/
│   ├── HybridMediaToolkit.swift    Nitro entry point (Swift)
│   ├── ImageProcessor.swift        CGImage crop và compress
│   ├── VideoProcessor.swift        AVFoundation trim, crop, compress, thumbnail
│   └── MediaToolkitErrors.swift    Định nghĩa lỗi
├── android/
│   └── src/main/java/com/mediatoolkit/
│       ├── HybridMediaToolkit.kt   Nitro entry point (Kotlin)
│       ├── ImageProcessor.kt       Bitmap crop và compress
│       └── VideoProcessor.kt       Media3 trim, crop, compress, thumbnail
├── nitrogen/                    File C++ và Swift/Kotlin bridge sinh tự động
└── example/                     App demo (Expo Dev Client)
```

---

## Đóng góp

Xem [CONTRIBUTING.md](./CONTRIBUTING.md) — [English](./CONTRIBUTING.md) | [Tiếng Việt](./CONTRIBUTING.vi.md)

## Giấy phép

MIT — xem [LICENSE](LICENSE)

## Tác giả

**thangdevalone** — quangthangvtlg@gmail.com  
GitHub: [https://github.com/thangdevalone](https://github.com/thangdevalone)
