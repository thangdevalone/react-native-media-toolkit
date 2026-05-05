import { NitroModules } from 'react-native-nitro-modules';
import type { MediaToolkit as MediaToolkitSpec } from './MediaToolkit.nitro';

export type {
  CropOptions,
  CompressImageOptions,
  TrimOptions,
  TrimAndCropOptions,
  VideoCropOptions,
  CompressVideoOptions,
  ThumbnailOptions,
  ThumbnailResult,
  FlipOptions,
  RotateOptions,
  SpeedOptions,
  ExtractAudioOptions,
  GeneratePreviewOptions,
  ProcessVideoOptions,
  ProcessImageOptions,
  MediaResult,
  MediaMetadata,
  LocationData,
} from './MediaToolkit.nitro';

// ─── Re-export ProgressEvent for backwards compatibility ──────────────────────
export interface ProgressEvent {
  /** Operation id (uri of the source file) */
  id: string;
  /** 0–100 */
  progress: number;
}

// ─── Create singleton HybridObject ────────────────────────────────────────────
const native = NitroModules.createHybridObject<MediaToolkitSpec>('MediaToolkit');

// ─── Public API ───────────────────────────────────────────────────────────────
export const MediaToolkit = {
  // ── Image ─────────────────────────────────────────────────────────────────

  /**
   * Crop an image by a relative region (x, y, width, height all in 0.0–1.0).
   */
  cropImage: native.cropImage.bind(native),

  /**
   * Compress (resize + quality reduce) an image.
   */
  compressImage: native.compressImage.bind(native),

  /**
   * Flip an image horizontally or vertically.
   */
  flipImage: native.flipImage.bind(native),

  /**
   * Rotate an image by 90, 180, or 270 degrees.
   */
  rotateImage: native.rotateImage.bind(native),

  // ── Video ─────────────────────────────────────────────────────────────────

  /**
   * Crop a video by a relative region — re-encodes the frames.
   */
  cropVideo: native.cropVideo.bind(native),

  /**
   * Trim a video to [startTime, endTime] in milliseconds.
   */
  trimVideo: native.trimVideo.bind(native),

  /**
   * Compress (re-encode) a video to lower bitrate / resolution.
   */
  compressVideo: native.compressVideo.bind(native),

  /**
   * Trim AND crop in a single encode pass — faster than running both separately.
   * Provide [startTime, endTime] ms plus crop region (x, y, width, height in 0–1).
   */
  trimAndCropVideo: native.trimAndCropVideo.bind(native),

  /**
   * Extract a single video frame as a JPEG thumbnail.
   * @param uri  Source video URI
   * @param options  timeMs, quality (0–100), maxWidth, outputPath
   */
  getThumbnail: native.getThumbnail.bind(native),

  /**
   * Flip a video horizontally or vertically.
   */
  flipVideo: native.flipVideo.bind(native),

  /**
   * Rotate a video by 90, 180, or 270 degrees.
   */
  rotateVideo: native.rotateVideo.bind(native),

  /**
   * Run multiple transformations (trim, crop, flip, rotate) on a video in a single pass.
   */
  processVideo: native.processVideo.bind(native),

  /**
   * Run multiple transformations (crop, flip, rotate) on an image.
   */
  processImage: native.processImage.bind(native),

  /**
   * Change video playback speed (e.g. 0.5x, 2.0x).
   */
  changeVideoSpeed: native.changeVideoSpeed.bind(native),

  /**
   * Extract audio track from a video file.
   */
  extractAudio: native.extractAudio.bind(native),

  /**
   * Generate an animated GIF preview from the video.
   */
  generateVideoPreview: native.generateVideoPreview.bind(native),

  /**
   * Get unified metadata (EXIF for images, Track metadata for videos)
   * Super fast, no memory bloat.
   */
  getMediaMetadata: native.getMediaMetadata.bind(native),
};

export default MediaToolkit;
