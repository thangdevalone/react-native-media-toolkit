import type { HybridObject } from 'react-native-nitro-modules';

// ─── Shared result type ────────────────────────────────────────────────────

export interface MediaResult {
  /** file:// URI of the output file */
  uri: string;
  /** File size in bytes */
  size: number;
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** Duration in milliseconds (video only, 0 for images) */
  duration: number;
  /** MIME type e.g. "image/jpeg" */
  mime: string;
}

export interface LocationData {
  latitude: number;
  longitude: number;
}

export interface MediaMetadata {
  /** 'image' or 'video' */
  type: string;
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** File size in bytes */
  size: number;
  /** Duration in milliseconds (0 for images) */
  duration: number;
  /** File extension or MIME type */
  mime: string;

  /** Camera Maker (e.g., Apple) */
  make?: string;
  /** Camera Model (e.g., iPhone 15 Pro) */
  model?: string;
  /** Creation or capture date */
  datetime?: string;
  
  /** Location data if available */
  location?: LocationData;

  // --- Photo Specific EXIF ---
  /** F-number (Aperture) */
  aperture?: number;
  /** Exposure time in seconds */
  exposureTime?: number;
  /** ISO speed rating */
  iso?: number;
  /** Focal length in mm */
  focalLength?: number;
}

// ─── Options types ─────────────────────────────────────────────────────────

export interface CropOptions {
  /** Left offset relative to image width (0.0–1.0) */
  x: number;
  /** Top offset relative to image height (0.0–1.0) */
  y: number;
  /** Crop width relative to image width (0.0–1.0) */
  width: number;
  /** Crop height relative to image height (0.0–1.0) */
  height: number;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface CompressImageOptions {
  /** JPEG/WebP quality 0–100 (default 80) */
  quality?: number;
  /** Maximum output width in px (aspect ratio preserved) */
  maxWidth?: number;
  /** Maximum output height in px (aspect ratio preserved) */
  maxHeight?: number;
  /** Output format: "jpeg" | "png" | "webp" (default "jpeg") */
  format?: string;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface TrimOptions {
  /** Trim start in milliseconds */
  startTime: number;
  /** Trim end in milliseconds */
  endTime: number;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface VideoCropOptions {
  /** Left offset relative to frame width (0.0–1.0) */
  x: number;
  /** Top offset relative to frame height (0.0–1.0) */
  y: number;
  /** Crop width relative to frame width (0.0–1.0) */
  width: number;
  /** Crop height relative to frame height (0.0–1.0) */
  height: number;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface CompressVideoOptions {
  /** Target file size in Megabytes. Computes an optimal bitrate based on duration. */
  targetSizeInMB?: number;
  /** Minimum resolution (shortest side in px) to protect quality when target size is small (default 720) */
  minResolution?: number;
  /** Quality preset: "low" | "medium" | "high" (default "medium", ignored if targetSizeInMB is set) */
  quality?: string;
  /** Target bitrate in bps (overrides quality preset, ignored if targetSizeInMB is set) */
  bitrate?: number;
  /** Max output width in px (aspect ratio preserved) */
  width?: number;
  /** Strip audio track from output (default false) */
  muteAudio?: boolean;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface ThumbnailOptions {
  /** Time in milliseconds to extract the frame (default 0) */
  timeMs?: number;
  /** Output quality 0–100 (default 80) */
  quality?: number;
  /** Max output width in px (aspect ratio preserved, default full res) */
  maxWidth?: number;
  /** Absolute output file path (optional, defaults to temp JPEG) */
  outputPath?: string;
}

export interface ThumbnailResult {
  /** file:// URI of the output JPEG */
  uri: string;
  /** Source video file size in bytes */
  size: number;
  /** Source video width in pixels (rotation-corrected) */
  width: number;
  /** Source video height in pixels (rotation-corrected) */
  height: number;
  /** Source video duration in milliseconds */
  duration: number;
}

export interface TrimAndCropOptions {
  /** Trim start in milliseconds */
  startTime: number;
  /** Trim end in milliseconds */
  endTime: number;
  /** Crop left offset relative to frame width (0.0–1.0) */
  x: number;
  /** Crop top offset relative to frame height (0.0–1.0) */
  y: number;
  /** Crop width relative to frame width (0.0–1.0) */
  width: number;
  /** Crop height relative to frame height (0.0–1.0) */
  height: number;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface FlipOptions {
  /** "horizontal" or "vertical" */
  direction: string;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface RotateOptions {
  /** Rotation angle in degrees: 90, 180, 270 */
  degrees: number;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface SpeedOptions {
  /** Speed multiplier: 0.25 to 4.0 */
  speed: number;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface ExtractAudioOptions {
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface GeneratePreviewOptions {
  /** Frames per second for the preview (default: 5) */
  fps?: number;
  /** Duration in milliseconds to capture from the start (default: 3000) */
  durationMs?: number;
  /** Maximum width of the preview (aspect ratio preserved, default: 0 = full size) */
  maxWidth?: number;
  /** Quality 0-100 (default: 80) */
  quality?: number;
  /** Absolute output file path (optional) */
  outputPath?: string;
}

export interface ProcessVideoOptions {
  startTime?: number;
  endTime?: number;
  cropX?: number;
  cropY?: number;
  cropWidth?: number;
  cropHeight?: number;
  flip?: string; // "horizontal" | "vertical"
  rotation?: number;
  outputPath?: string;
}

export interface ProcessImageOptions {
  cropX?: number;
  cropY?: number;
  cropWidth?: number;
  cropHeight?: number;
  flip?: string; // "horizontal" | "vertical"
  rotation?: number;
  outputPath?: string;
}

// ─── HybridObject spec ─────────────────────────────────────────────────────

export interface MediaToolkit
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  // ── Image ────────────────────────────────────────────────────────────────
  cropImage(uri: string, options: CropOptions): Promise<MediaResult>;
  compressImage(
    uri: string,
    options: CompressImageOptions
  ): Promise<MediaResult>;
  flipImage(uri: string, options: FlipOptions): Promise<MediaResult>;
  rotateImage(uri: string, options: RotateOptions): Promise<MediaResult>;

  // ── Video ────────────────────────────────────────────────────────────────
  cropVideo(uri: string, options: VideoCropOptions): Promise<MediaResult>;
  trimVideo(uri: string, options: TrimOptions): Promise<MediaResult>;
  /** Trim + crop in a SINGLE encode pass — faster, no quality loss from double-encode */
  trimAndCropVideo(uri: string, options: TrimAndCropOptions): Promise<MediaResult>;
  /** Extract a single frame from a video as a JPEG */
  getThumbnail(uri: string, options?: ThumbnailOptions): Promise<ThumbnailResult>;
  compressVideo(
    uri: string,
    options: CompressVideoOptions
  ): Promise<MediaResult>;
  flipVideo(uri: string, options: FlipOptions): Promise<MediaResult>;
  rotateVideo(uri: string, options: RotateOptions): Promise<MediaResult>;

  /** Multi-transform video: trim, crop, flip, rotate in a single pass */
  processVideo(uri: string, options: ProcessVideoOptions): Promise<MediaResult>;
  /** Multi-transform image: crop, flip, rotate in a single pass */
  processImage(uri: string, options: ProcessImageOptions): Promise<MediaResult>;
  /** Change video playback speed (0.25x - 4.0x) */
  changeVideoSpeed(uri: string, options: SpeedOptions): Promise<MediaResult>;
  /** Extract audio track from video as m4a/mp4 */
  extractAudio(uri: string, options: ExtractAudioOptions): Promise<MediaResult>;
  /** Generate an animated GIF preview from the video */
  generateVideoPreview(uri: string, options: GeneratePreviewOptions): Promise<MediaResult>;
  
  /** Get unified metadata (EXIF for images, MediaMetadata for videos) */
  getMediaMetadata(uri: string): Promise<MediaMetadata>;
}
