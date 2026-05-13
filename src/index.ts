import { NitroModules } from 'react-native-nitro-modules';
import type { MediaToolkit as MediaToolkitSpec } from './MediaToolkit.nitro';

import type {
  CropOptions as NCropOptions,
  CompressImageOptions as NCompressImageOptions,
  ThumbnailOptions as NThumbnailOptions,
  FlipOptions as NFlipOptions,
  RotateOptions as NRotateOptions,
  ProcessImageOptions as NProcessImageOptions,
  SplitImageOptions,
  TrimOptions,
  TrimAndCropOptions,
  VideoCropOptions,
  CompressVideoOptions,
  ThumbnailResult,
  SpeedOptions,
  ExtractAudioOptions,
  GeneratePreviewOptions,
  ProcessVideoOptions,
  MediaResult,
  MediaMetadata,
  LocationData,
} from './MediaToolkit.nitro';

export type {
  SplitImageOptions,
  TrimOptions,
  TrimAndCropOptions,
  VideoCropOptions,
  CompressVideoOptions,
  ThumbnailResult,
  SpeedOptions,
  ExtractAudioOptions,
  GeneratePreviewOptions,
  ProcessVideoOptions,
  MediaResult,
  MediaMetadata,
  LocationData,
};

export type CropOptions = Omit<NCropOptions, 'cornerRadius'> & { cornerRadius?: number | string };
export type CompressImageOptions = Omit<NCompressImageOptions, 'cornerRadius'> & { cornerRadius?: number | string };
export type ThumbnailOptions = Omit<NThumbnailOptions, 'cornerRadius'> & { cornerRadius?: number | string };
export type FlipOptions = Omit<NFlipOptions, 'cornerRadius'> & { cornerRadius?: number | string };
export type RotateOptions = Omit<NRotateOptions, 'cornerRadius'> & { cornerRadius?: number | string };
export type ProcessImageOptions = Omit<NProcessImageOptions, 'cornerRadius'> & { cornerRadius?: number | string };

const parseRadius = (val?: number | string): number | undefined => {
  if (val === undefined) return undefined;
  if (typeof val === 'number') return Math.max(0, val);
  if (typeof val === 'string') {
    const cleanVal = val.replace(/-/g, '').trim();
    let cr = parseFloat(cleanVal) || 0;
    if (cr < 0) cr = 0;
    if (cleanVal.endsWith('%')) {
      if (cr > 100) cr = 100;
      return -cr;
    }
    return cr;
  }
  return undefined;
};


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
  cropImage: (uri: string, opts: CropOptions) => native.cropImage(uri, { ...opts, cornerRadius: parseRadius(opts.cornerRadius) }),

  /**
   * Compress (resize + quality reduce) an image.
   */
  compressImage: (uri: string, opts: CompressImageOptions) => native.compressImage(uri, { ...opts, cornerRadius: parseRadius(opts.cornerRadius) }),

  /**
   * Split an image into a rows x columns grid without resizing the source pixels.
   */
  splitImage: native.splitImage.bind(native),

  /**
   * Flip an image horizontally or vertically.
   */
  flipImage: (uri: string, opts: FlipOptions) => native.flipImage(uri, { ...opts, cornerRadius: parseRadius(opts.cornerRadius) }),

  /**
   * Rotate an image by 90, 180, or 270 degrees.
   */
  rotateImage: (uri: string, opts: RotateOptions) => native.rotateImage(uri, { ...opts, cornerRadius: parseRadius(opts.cornerRadius) }),

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
  getThumbnail: (uri: string, opts?: ThumbnailOptions) => native.getThumbnail(uri, opts ? { ...opts, cornerRadius: parseRadius(opts.cornerRadius) } : undefined),

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
  processImage: (uri: string, opts: ProcessImageOptions) => native.processImage(uri, { ...opts, cornerRadius: parseRadius(opts.cornerRadius) }),

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
   * Concatenate multiple local video clips into a single file using AVFoundation
   * passthrough (iOS) / Media3 passthrough Transformer (Android). No re-encode —
   * frame-accurate, near-instant joining of compatible clips. Resolves with the
   * sum of input durations in seconds.
   */
  concatVideos: native.concatVideos.bind(native),

  /**
   * Get unified metadata (EXIF for images, Track metadata for videos)
   * Super fast, no memory bloat.
   */
  getMediaMetadata: native.getMediaMetadata.bind(native),
};

export default MediaToolkit;
