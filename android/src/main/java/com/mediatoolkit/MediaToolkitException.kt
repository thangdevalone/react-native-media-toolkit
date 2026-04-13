package com.margelo.nitro.com.mediatoolkit

/** Typed errors thrown by the media processors — mirrors iOS [MediaToolkitError]. */
sealed class MediaToolkitException(message: String) : Exception(message) {
  /** Bad or unreadable input (wrong URI, missing file, invalid params). */
  class InvalidInput(detail: String) : MediaToolkitException("MediaToolkit invalid input: $detail")

  /** A processing step failed at runtime (encode error, frame extraction, etc.). */
  class ProcessingFailed(detail: String) : MediaToolkitException("MediaToolkit processing failed: $detail")

  /** The requested operation is not supported on this device / OS version. */
  class Unsupported(detail: String) : MediaToolkitException("MediaToolkit unsupported: $detail")
}
