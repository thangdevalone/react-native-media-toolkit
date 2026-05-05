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
| iOS | 16.0+ |
| Android | API 24+ (Android 7.0) / Android 15 (16 KB Page Size) Ready |

> **Expo note:** This library requires a native build. It cannot run in Expo Go.  
> Use `expo run:ios` or `expo run:android` instead.

---

## Features

| Feature | iOS | Android |
|---|---|---|
| Crop image | AVFoundation / CGImage | Bitmap |
| Compress image | CGImageSource (OOM-free) | BitmapFactory / inSampleSize |
| Flip / Rotate image | CGImage / CoreGraphics | Bitmap |
| Multi-transform image | CGImage / CoreGraphics | Bitmap |
| Trim video (start/end in ms) | AVAssetExportSession | Media3 Transformer |
| Crop video (relative region) | AVMutableVideoComposition | Media3 Presentation |
| Flip / Rotate video | AVMutableVideoComposition | Media3 Presentation |
| Trim + Crop in single pass | AVMutableVideoComposition | Media3 Transformer |
| Multi-transform video | AVMutableVideoComposition | Media3 Transformer |
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
  x: 0.25,      // required — left offset relative to image width (0.0–1.0)
  y: 0.25,      // required — top offset relative to image height (0.0–1.0)
  width: 0.5,   // required — crop width relative to image width (0.0–1.0)
  height: 0.5,  // required — crop height relative to image height (0.0–1.0)
  outputPath: '/custom/path/out.jpg', // optional
});
console.log(result.uri, result.width, result.height);
```

### Compress image

```typescript
const result = await MediaToolkit.compressImage(imageUri, {
  quality: 70,       // optional — 0–100, default 80
  maxWidth: 1080,    // optional — max output width, aspect ratio preserved
  maxHeight: 1920,   // optional — max output height, aspect ratio preserved
  format: 'jpeg',    // optional — 'jpeg' | 'png' | 'webp', default 'jpeg'
});
```

### Flip image

```typescript
const result = await MediaToolkit.flipImage(imageUri, {
  direction: 'horizontal', // 'horizontal' | 'vertical'
});
```

### Rotate image

```typescript
const result = await MediaToolkit.rotateImage(imageUri, {
  degrees: 90, // 90, 180, 270
});
```

### Process image (Multi-transform)

Run multiple operations in a single pass to save processing time and memory.
```typescript
const result = await MediaToolkit.processImage(imageUri, {
  cropX: 0.1,
  cropY: 0.1,
  cropWidth: 0.8,
  cropHeight: 0.8,
  flip: 'horizontal',
  rotation: 90,
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

The compressor supports two modes. Use **one** of them:

**Mode 1 — Smart compress to a target file size** (recommended):
```typescript
const result = await MediaToolkit.compressVideo(videoUri, {
  targetSizeInMB: 8,   // required for this mode — target output size in MB
  minResolution: 480,  // optional — minimum short-edge resolution (default 720)
  muteAudio: false,    // optional — strip audio track (default false)
  width: 1280,         // optional — max output width, aspect ratio preserved
});
```

**Mode 2 — Quality preset or explicit bitrate**:
```typescript
const result = await MediaToolkit.compressVideo(videoUri, {
  quality: 'medium',   // optional — 'low' | 'medium' | 'high' (default 'medium')
  bitrate: 2_000_000,  // optional — explicit bitrate in bps (overrides quality)
  muteAudio: false,    // optional — strip audio track (default false)
  width: 1280,         // optional — max output width, aspect ratio preserved
});
```

> **Note:** `targetSizeInMB`, `quality`, and `bitrate` are all optional — but the library needs at least one signal to determine bitrate. If you pass nothing, it defaults to `quality: 'medium'` (~4 Mbps). `targetSizeInMB` takes highest priority; `bitrate` overrides `quality`.

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

### Flip video

```typescript
const result = await MediaToolkit.flipVideo(videoUri, {
  direction: 'horizontal', // 'horizontal' | 'vertical'
});
```

### Rotate video

```typescript
const result = await MediaToolkit.rotateVideo(videoUri, {
  degrees: 90, // 90, 180, 270
});
```

### Process video (Multi-transform)

Run multiple video operations in a single pass (trim, crop, flip, rotate).
```typescript
const result = await MediaToolkit.processVideo(videoUri, {
  startTime: 1000,
  endTime: 8000,
  cropX: 0.1,
  cropY: 0.1,
  cropWidth: 0.8,
  cropHeight: 0.8,
  flip: 'horizontal',
  rotation: 90,
});
```

### Change video speed

```typescript
const result = await MediaToolkit.changeVideoSpeed(videoUri, {
  speed: 2.0, // 0.25x to 4.0x
});
```

### Extract audio

Extracts the audio track from a video and saves it as an `m4a` file.
```typescript
const audio = await MediaToolkit.extractAudio(videoUri, {});
// audio.uri -> file:///.../audio.m4a
```

### Generate video preview (GIF)

Generates an animated GIF preview from the video frames natively without FFmpeg.
```typescript
const preview = await MediaToolkit.generateVideoPreview(videoUri, {
  durationMs: 3000, // Duration to capture (default 3000ms)
  fps: 5,           // Frames per second (default 5)
  maxWidth: 0,      // 0 = full source width; set e.g. 320 to downscale
});
```

---

## API Reference

> **Convention:** `Required` = must be provided. `Optional` = has a sensible default or can be omitted entirely.

### `cropImage(uri, options): Promise<MediaResult>`

| Option | Type | Required | Description |
|---|---|---|---|
| `x` | `number` | **Required** | Left offset relative to image width (0.0–1.0) |
| `y` | `number` | **Required** | Top offset relative to image height (0.0–1.0) |
| `width` | `number` | **Required** | Crop width relative to image width (0.0–1.0) |
| `height` | `number` | **Required** | Crop height relative to image height (0.0–1.0) |
| `outputPath` | `string` | Optional | Absolute path for the output file. Defaults to a temp file. |

### `compressImage(uri, options): Promise<MediaResult>`

All options are optional. Pass an empty object `{}` to use all defaults.

| Option | Type | Default | Description |
|---|---|---|---|
| `quality` | `number` | `80` | JPEG/WebP encode quality (0–100) |
| `maxWidth` | `number` | original | Max output width in px (aspect ratio preserved) |
| `maxHeight` | `number` | original | Max output height in px (aspect ratio preserved) |
| `format` | `string` | `'jpeg'` | Output format: `'jpeg'` \| `'png'` \| `'webp'` |
| `outputPath` | `string` | temp file | Absolute path for the output file |

### `flipImage(uri, options): Promise<MediaResult>`
### `flipVideo(uri, options): Promise<MediaResult>`

| Option | Type | Required | Description |
|---|---|---|---|
| `direction` | `string` | **Required** | `'horizontal'` or `'vertical'` |
| `outputPath` | `string` | Optional | Absolute path for the output file. Defaults to a temp file. |

### `rotateImage(uri, options): Promise<MediaResult>`
### `rotateVideo(uri, options): Promise<MediaResult>`

| Option | Type | Required | Description |
|---|---|---|---|
| `degrees` | `number` | **Required** | `90`, `180`, or `270` |
| `outputPath` | `string` | Optional | Absolute path for the output file. Defaults to a temp file. |

### `processImage(uri, options): Promise<MediaResult>`

Multi-transform image in a single pass. All options are **optional**.

| Option | Type | Description |
|---|---|---|
| `cropX` | `number` | Crop left offset relative to image width (0.0–1.0) |
| `cropY` | `number` | Crop top offset relative to image height (0.0–1.0) |
| `cropWidth` | `number` | Crop width relative to image width (0.0–1.0) |
| `cropHeight` | `number` | Crop height relative to image height (0.0–1.0) |
| `flip` | `string` | `'horizontal'` or `'vertical'` |
| `rotation` | `number` | `90`, `180`, or `270` |
| `outputPath` | `string` | Absolute path for the output file. Defaults to a temp file. |

### `trimVideo(uri, options): Promise<MediaResult>`

| Option | Type | Required | Description |
|---|---|---|---|
| `startTime` | `number` | **Required** | Trim start position in milliseconds |
| `endTime` | `number` | **Required** | Trim end position in milliseconds |
| `outputPath` | `string` | Optional | Absolute path for the output file. Defaults to a temp file. |

### `cropVideo(uri, options): Promise<MediaResult>`

Same relative coordinate system as `cropImage` — all values in the range (0.0–1.0).

| Option | Type | Required | Description |
|---|---|---|---|
| `x` | `number` | **Required** | Left offset relative to frame width (0.0–1.0) |
| `y` | `number` | **Required** | Top offset relative to frame height (0.0–1.0) |
| `width` | `number` | **Required** | Crop width relative to frame width (0.0–1.0) |
| `height` | `number` | **Required** | Crop height relative to frame height (0.0–1.0) |
| `outputPath` | `string` | Optional | Absolute path for the output file. Defaults to a temp file. |

### `trimAndCropVideo(uri, options): Promise<MediaResult>`

Combines trim and crop into a **single encode pass** — faster and avoids double-encode quality loss.

| Option | Type | Required | Description |
|---|---|---|---|
| `startTime` | `number` | **Required** | Trim start position in milliseconds |
| `endTime` | `number` | **Required** | Trim end position in milliseconds |
| `x` | `number` | **Required** | Crop left offset relative to frame width (0.0–1.0) |
| `y` | `number` | **Required** | Crop top offset relative to frame height (0.0–1.0) |
| `width` | `number` | **Required** | Crop width relative to frame width (0.0–1.0) |
| `height` | `number` | **Required** | Crop height relative to frame height (0.0–1.0) |
| `outputPath` | `string` | Optional | Absolute path for the output file. Defaults to a temp file. |

### `processVideo(uri, options): Promise<MediaResult>`

Multi-transform video in a single pass (trim, crop, flip, rotate). All options are **optional**.

| Option | Type | Description |
|---|---|---|
| `startTime` | `number` | Trim start position in milliseconds |
| `endTime` | `number` | Trim end position in milliseconds |
| `cropX` | `number` | Crop left offset relative to frame width (0.0–1.0) |
| `cropY` | `number` | Crop top offset relative to frame height (0.0–1.0) |
| `cropWidth` | `number` | Crop width relative to frame width (0.0–1.0) |
| `cropHeight` | `number` | Crop height relative to frame height (0.0–1.0) |
| `flip` | `string` | `'horizontal'` or `'vertical'` |
| `rotation` | `number` | `90`, `180`, or `270` |
| `outputPath` | `string` | Absolute path for the output file. Defaults to a temp file. |

### `compressVideo(uri, options): Promise<MediaResult>`

All options are **optional**. The bitrate strategy follows this priority:

1. **`targetSizeInMB`** → smart-compress: calculates optimal bitrate and resolution from duration + target size *(highest priority)*
2. **`bitrate`** → explicit bitrate override *(takes priority over `quality`)*
3. **`quality`** → preset mapping: `low` ≈ 1 Mbps · `medium` ≈ 4 Mbps · `high` ≈ 8 Mbps *(default)*

If none of the three are passed, the library falls back to `quality: 'medium'`.

| Option | Type | Default | Description |
|---|---|---|---|
| `targetSizeInMB` | `number` | — | **Optional.** Target output file size in MB. When set, overrides `quality` and `bitrate`. |
| `minResolution` | `number` | `720` | **Optional.** Minimum short-edge resolution (px) when using `targetSizeInMB`. Prevents over-downscaling. |
| `quality` | `string` | `'medium'` | **Optional.** Preset: `'low'` \| `'medium'` \| `'high'`. Ignored if `targetSizeInMB` or `bitrate` is set. |
| `bitrate` | `number` | — | **Optional.** Explicit target bitrate in bps. Overrides `quality`; ignored if `targetSizeInMB` is set. |
| `width` | `number` | original | **Optional.** Max output width in px (aspect ratio preserved). |
| `muteAudio` | `boolean` | `false` | **Optional.** Strip audio track from the output. |
| `outputPath` | `string` | temp file | **Optional.** Absolute path for the output file. |

### `getThumbnail(uri, options?): Promise<ThumbnailResult>`

`options` itself is optional — pass nothing to extract a full-res JPEG at time 0.

| Option | Type | Default | Description |
|---|---|---|---|
| `timeMs` | `number` | `0` | Frame time in milliseconds |
| `quality` | `number` | `80` | JPEG output quality (0–100) |
| `maxWidth` | `number` | original | Max thumbnail width in px (aspect ratio preserved) |
| `outputPath` | `string` | temp file | Absolute path for the output JPEG |

### `changeVideoSpeed(uri, options): Promise<MediaResult>`

| Option | Type | Default | Description |
|---|---|---|---|
| `speed` | `number` | **Required** | Speed multiplier (e.g. 0.5 for half speed, 2.0 for double speed). Supported range: 0.25 to 4.0. |
| `outputPath` | `string` | temp file | **Optional.** Absolute path for the output file. |

### `extractAudio(uri, options): Promise<MediaResult>`

| Option | Type | Default | Description |
|---|---|---|---|
| `outputPath` | `string` | temp file | **Optional.** Absolute path for the output `.m4a` file. |

### `generateVideoPreview(uri, options): Promise<MediaResult>`

Generates an animated GIF natively.

| Option | Type | Default | Description |
|---|---|---|---|
| `fps` | `number` | `5` | **Optional.** Frames per second for the preview. |
| `durationMs` | `number` | `3000` | **Optional.** Duration in milliseconds to capture from the start. |
| `maxWidth` | `number` | `0` | **Optional.** Maximum width of the preview (aspect ratio preserved). Use `0` for full source size. |
| `quality` | `number` | `80` | **Optional.** Quality 0-100 (mapped to internal encoder settings). |
| `outputPath` | `string` | temp file | **Optional.** Absolute path for the output `.gif` file. |

### `getMediaMetadata(uri): Promise<MediaMetadata>`

Gets unified metadata directly from the native source. For images, extracts deep EXIF/TIFF/GPS data. For videos, extracts track sizes, location, and creation info natively without bloated parsing.

* No options required. It automatically sniffs the file type.

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

interface MediaMetadata {
  type: string;     // 'image' | 'video'
  width: number;
  height: number;
  size: number;
  duration: number; // 0 for images
  mime: string;
  make?: string;    // Camera Make (e.g. Apple)
  model?: string;   // Camera Model
  datetime?: string;
  location?: { latitude: number; longitude: number };
  
  // EXIF specific (Images only)
  aperture?: number;
  exposureTime?: number;
  iso?: number;
  focalLength?: number;
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

| Library | Native Engine | JS Bridge | Image Support | Video Support | Trim (no re-encode) | Multi-transform (1-pass) |
|---|---|---|---|---|---|---|
| **react-native-media-toolkit** | AVFoundation / Media3 | **JSI (Nitro)** | **Yes** (OOM-free) | **Yes** | **Yes** | **Yes** |
| `react-native-compressor` | AVFoundation / MediaCodec | Bridge | Yes | Yes | No | No |
| `react-native-video-trim` | AVFoundation / FFmpegKit | Bridge | No | Yes (UI included) | iOS only | No |

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
│       ├── HybridMediaToolkit.kt     Nitro entry point (Kotlin)
│       ├── ImageProcessor.kt         Bitmap crop and compress
│       ├── VideoProcessor.kt         Media3 trim, crop, compress, thumbnail
│       └── MediaToolkitException.kt  Error definitions
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
