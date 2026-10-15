# Video compression regressions

Both native implementations consume the same 25 range cases in
`tests/fixtures/video-trim-ranges.tsv`. These cover omitted and one-sided bounds,
explicit zero, a full range, empty and reversed ranges, negative and out-of-bounds
values, unknown duration, non-finite values, and a sub-millisecond range.

Android runs the contract through JUnit as part of `yarn example build:android`.
To run only that test after generating the example Android project:

```sh
cd example/android
./gradlew :react-native-media-toolkit:testDebugUnitTest
```

The iOS CI job compiles the production Foundation helpers and runs the shared
range contract plus five file-content checks for the compression fallback.
On macOS, run from the repository root:

```sh
swiftc ios/VideoTrimRange.swift ios/VideoCompressionFallback.swift tests/native/swift/main.swift -o /tmp/video-compression-tests
/tmp/video-compression-tests tests/fixtures/video-trim-ranges.tsv
```

The fallback checks use a larger encoded output with different contents from
the source. A trimmed export must retain the output bytes, while an untrimmed,
unmuted export can still revert to the smaller source. Muted and already-smaller
outputs must retain their bytes as well.

These tests do not exercise device codecs. For an end-to-end check, compress a
middle range of a local clip on iOS using an explicit bitrate large enough that
the encoded range exceeds the source size and `muteAudio: false`; confirm the
output still contains only the selected range. Repeat with the preset pipeline,
one-sided ranges, and `targetSizeInMB` on iOS and Android.
