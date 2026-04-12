# react-native-media-toolkit

Read this in: [Tiếng Việt](./README.vi.md)

---

Native image and video processing for React Native — crop, trim, compress, and thumbnail extraction.  
Built on **Nitro Modules** (JSI), using `AVFoundation` on iOS and **Jetpack Media3 Transformer** on Android. No FFmpeg dependency.

[![npm](https://img.shields.io/npm/v/react-native-media-toolkit)](https://www.npmjs.com/package/react-native-media-toolkit)
[![license](https://img.shields.io/npm/l/react-native-media-toolkit)](LICENSE)

<p align="center">
  <img src=".github/images/1.png" width="200" />
  &nbsp;&nbsp;
  <img src=".github/images/2.png" width="200" />
  &nbsp;&nbsp;
  <img src=".github/images/3.png" width="200" />
</p>

---

## Compatibility

| Environment | Support |
|---|---|
| React Native CLI (New Architecture) | Supported |
| Expo with Dev Client / Custom Build | Supported |
| Expo Go | Not supported (requires native build) |
| React Native | 0.75+ (New Architecture required) |
| iOS | 15.1+ |
| Android | API 24+ (Android 7.0) |

> **Expo note:** This library requires a native build. It cannot run in Expo Go.  
> Use `expo run:ios` or `expo run:android` instead.

---

## Features

| Feature | iOS | Android |
|---|---|---|
| Crop image | AVFoundation / CGImage | Bitmap |
| Compress image | CGImageSource (OOM-free) | BitmapFactory / inSampleSize |
| Trim video (start/end in ms) | AVAssetExportSession | Media3 Transformer |
| Crop video (relative region) | AVMutableVideoComposition | Media3 Presentation |
| Trim + Crop in single pass | AVMutableVideoComposition | Media3 Transformer |
| Compress video | AVAssetExportSession presets | Media3 Transformer |
| Extract thumbnail from video | AVAssetImageGenerator | MediaMetadataRetriever |

All crop coordinates use a **relative (0.0–1.0) system** — independent of screen resolution.

---

## Installation

```sh
npm install react-native-media-toolkit react-native-nitro-modules
# or
yarn add react-native-media-toolkit react-native-nitro-modules
```

**iOS:**
```sh
cd ios && pod install
```

**Android:** No extra steps. Gradle resolves Media3 automatically.

---

## Usage

```typescript
import { MediaToolkit } from 'react-native-media-toolkit';
```

### Crop image

```typescript
const result = await MediaToolkit.cropImage(imageUri, {
  x: 0.25,      // left offset relative to image width (0.0–1.0)
  y: 0.25,      // top offset relative to image height (0.0–1.0)
  width: 0.5,   // crop width relative to image width (0.0–1.0)
  height: 0.5,  // crop height relative to image height (0.0–1.0)
});
console.log(result.uri, result.width, result.height);
```

### Compress image

```typescript
const result = await MediaToolkit.compressImage(imageUri, {
  quality: 70,       // 0–100, default 80
  maxWidth: 1080,    // max output width, aspect ratio preserved
  format: 'jpeg',    // 'jpeg' | 'png' | 'webp'
});
```

### Trim video

```typescript
const result = await MediaToolkit.trimVideo(videoUri, {
  startTime: 2000,  // start in milliseconds
  endTime: 7000,    // end in milliseconds
});
```

### Crop video

```typescript
const result = await MediaToolkit.cropVideo(videoUri, {
  x: 0.1,
  y: 0.1,
  width: 0.8,
  height: 0.8,
});
```

### Trim + Crop in one pass

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

> Faster than running trim and crop separately — only one encode pass.

### Compress video

```typescript
const result = await MediaToolkit.compressVideo(videoUri, {
  targetSizeInMB: 8,       // Smart compress: calculate optimal bitrate for ~8MB
  minResolution: 720,      // Optional: floor resolution for smart compress
  muteAudio: true,         // Optional: strip audio track
  quality: 'medium',       // 'low' | 'medium' | 'high' (ignored if targetSizeInMB exists)
  width: 1080,             // max output width, aspect ratio preserved
});
```

### Extract thumbnail

```typescript
const thumb = await MediaToolkit.getThumbnail(videoUri, {
  timeMs: 3000,    // frame time in milliseconds, default 0
  quality: 85,     // 0–100, default 80
  maxWidth: 720,   // max thumbnail width (does not affect returned metadata)
});
// thumb.uri      → thumbnail JPEG file
// thumb.width    → source video width (rotation-corrected)
// thumb.height   → source video height
// thumb.size     → source video file size in bytes
// thumb.duration → source video duration in ms
```

---

## API Reference

### `cropImage(uri, options): Promise<MediaResult>`

| Option | Type | Required | Description |
|---|---|---|---|
| `x` | number | Yes | Left offset (0.0–1.0) |
| `y` | number | Yes | Top offset (0.0–1.0) |
| `width` | number | Yes | Crop width (0.0–1.0) |
| `height` | number | Yes | Crop height (0.0–1.0) |
| `outputPath` | string | No | Absolute path for output file |

### `compressImage(uri, options): Promise<MediaResult>`

| Option | Type | Default | Description |
|---|---|---|---|
| `quality` | number | 80 | JPEG/WebP quality (0–100) |
| `maxWidth` | number | original | Max output width |
| `maxHeight` | number | original | Max output height |
| `format` | string | `'jpeg'` | `'jpeg'` / `'png'` / `'webp'` |
| `outputPath` | string | — | Absolute output path |

### `trimVideo(uri, options): Promise<MediaResult>`

| Option | Type | Required | Description |
|---|---|---|---|
| `startTime` | number | Yes | Trim start in milliseconds |
| `endTime` | number | Yes | Trim end in milliseconds |
| `outputPath` | string | No | Absolute output path |

### `cropVideo(uri, options): Promise<MediaResult>`

Same coordinate system as `cropImage`. All values are relative (0.0–1.0).

### `trimAndCropVideo(uri, options): Promise<MediaResult>`

Combines trim and crop into a single encode pass.

| Option | Type | Required | Description |
|---|---|---|---|
| `startTime` | number | Yes | Trim start in milliseconds |
| `endTime` | number | Yes | Trim end in milliseconds |
| `x` | number | Yes | Crop left offset (0.0–1.0) |
| `y` | number | Yes | Crop top offset (0.0–1.0) |
| `width` | number | Yes | Crop width (0.0–1.0) |
| `height` | number | Yes | Crop height (0.0–1.0) |
| `outputPath` | string | No | Absolute output path |

### `compressVideo(uri, options): Promise<MediaResult>`

| Option | Type | Default | Description |
|---|---|---|---|
| `targetSizeInMB`| number | — | Smart compress to target file size |
| `minResolution`| number | 720 | Forces Target Resolution Bound |
| `muteAudio` | boolean| `false` | Strip audio track from output |
| `quality` | string | `'medium'` | `'low'` / `'medium'` / `'high'` |
| `bitrate` | number | preset | Target bitrate in bps |
| `width` | number | original | Max output width |
| `outputPath` | string | — | Absolute output path |

### `getThumbnail(uri, options?): Promise<ThumbnailResult>`

| Option | Type | Default | Description |
|---|---|---|---|
| `timeMs` | number | 0 | Frame time in milliseconds |
| `quality` | number | 80 | Output quality (0–100) |
| `maxWidth` | number | original | Max output width |
| `outputPath` | string | — | Absolute output path |

### Return types

```typescript
interface MediaResult {
  uri: string;      // file:// URI of the output file
  size: number;     // file size in bytes
  width: number;    // output width in pixels
  height: number;   // output height in pixels
  duration: number; // duration in ms (0 for images)
  mime: string;     // MIME type, e.g. 'video/mp4'
}

interface ThumbnailResult {
  uri: string;      // file:// URI of the output JPEG thumbnail
  size: number;     // source video file size in bytes
  width: number;    // source video width in pixels (rotation-corrected)
  height: number;   // source video height in pixels (rotation-corrected)
  duration: number; // source video duration in milliseconds
}
```

> **Note:** `width`, `height`, `size`, and `duration` in `ThumbnailResult` refer to the **source video** metadata — not the thumbnail image. This makes `getThumbnail` a lightweight way to probe video metadata without processing the file.

---

## Custom UI

This library is **headless** — it provides native processing logic only, without any built-in UI.  
You are free to build any trim timeline, crop overlay, or progress indicator that fits your app design.

The example app (`example/src/App.tsx`) includes reference implementations of:
- `VideoTrimBar` — a timeline scrubber with dual handles and thumbnail strip
- `CropOverlay` — a draggable crop box with corner resize handles

You can copy these components directly into your project and adapt them as needed.



---

## Performance

This library is designed around two principles: avoid unnecessary work and stay on the native thread.

### No bridge overhead

All API calls go through **JSI (JavaScript Interface)** via Nitro Modules. There is no JSON serialization between JS and native — the call is a direct C++ function call. This eliminates the main bottleneck of the old Bridge architecture.

### Trim without re-encoding

`trimVideo` uses `AVAssetExportPresetPassthrough` on iOS and a keyframe-aligned cut on Android. The compressed bitstream is copied as-is — no decode, no re-encode. A 30-second video trims in under 1 second regardless of resolution.

### Single-pass trim + crop

Running `trimVideo` then `cropVideo` sequentially means two full encode passes: decode → encode → decode → encode. `trimAndCropVideo` does both in one session: decode → encode once. This halves the processing time and avoids quality loss from double encoding.

### Memory-Efficient Image Processing (OOM-Free)

Standard image processing operations can cause Out-Of-Memory (OOM) exceptions when decoding high-resolution images (e.g., 40MP+). To prevent this, the library handles decoding via **Load-Time Downsampling**:
- **Android:** Utilizes `BitmapFactory.Options.inSampleSize` to subsample the image during the hardware decoding phase, bypassing full-resolution memory allocation entirely.
- **iOS:** Uses `CGImageSourceCreateThumbnailAtIndex` to instruct `ImageIO` to decode and downscale directly from the file descriptor buffer.

### Smart Video Compression

The `compressVideo` API provides a dynamically balanced encoding strategy via the `targetSizeInMB` flag. When provided, the library will:
- Calculate a bounded target `bitrate` mapped by the `duration` of the media track.
- Adjust the output resolution dynamically, floor-bounded by `minResolution` to maintain pixel clarity at constrained bitrates.
- Optionally strip the audio track (`muteAudio`) to allocate the entire output bandwidth to the visual presentation.

### Comparison with common alternatives

| Library | Native engine | JS bridge | Trim (no re-encode) | Single-pass trim+crop |
|---|---|---|---|---|
| react-native-media-toolkit | AVFoundation / Media3 | JSI (no overhead) | Yes | Yes |
| react-native-video-trim | AVFoundation / FFmpegKit | Bridge | iOS only | No |
| react-native-compressor | AVFoundation / MediaCodec | Bridge | No | No |
| ffmpeg-kit-react-native | FFmpeg (software) | Bridge | No | No |

Note: FFmpegKit is the most flexible option for complex pipelines. This library is optimized for the common cases: trim, crop, compress, and thumbnail extraction.

---

## Architecture

```
react-native-media-toolkit/
├── src/
│   ├── MediaToolkit.nitro.ts   Nitro HybridObject spec + TypeScript types
│   └── index.ts                Public JS/TS API
├── ios/
│   ├── HybridMediaToolkit.swift    Nitro entry point (Swift)
│   ├── ImageProcessor.swift        CGImage crop and compress
│   ├── VideoProcessor.swift        AVFoundation trim, crop, compress, thumbnail
│   └── MediaToolkitErrors.swift    Error definitions
├── android/
│   └── src/main/java/com/mediatoolkit/
│       ├── HybridMediaToolkit.kt   Nitro entry point (Kotlin)
│       ├── ImageProcessor.kt       Bitmap crop and compress
│       └── VideoProcessor.kt       Media3 trim, crop, compress, thumbnail
├── nitrogen/                    Generated C++ and Swift/Kotlin bridge files
└── example/                     Demo app (Expo Dev Client)
```

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md)

## License

MIT — see [LICENSE](LICENSE)

## Author

**thangdevalone** — quangthangvtlg@gmail.com  
GitHub: [https://github.com/thangdevalone](https://github.com/thangdevalone)
