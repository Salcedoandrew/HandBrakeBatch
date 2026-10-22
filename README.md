# HandBrake Batch

A native macOS (Swift/SwiftUI) rewrite of [HandBrakeBatch](https://github.com/taglia/handbrakebatch): drop a pile of videos on the window and convert them all with HandBrake.

## Requirements
- macOS 13 or later (universal: Apple Silicon + Intel)
- HandBrakeCLI: `brew install handbrake` (found in /opt/homebrew/bin, /usr/local/bin, `$PATH`, or `$HANDBRAKECLI`)

## Build and install
Only the Xcode Command Line Tools are needed.

```sh
./build.sh            # builds build/HandBrake Batch.app (ad-hoc signed)
./build.sh --install  # also copies it to /Applications
```

## Features
- Presets: HandBrake's built-in presets (from `HandBrakeCLI --preset-list`, used with `-Z`), your presets from
  `~/Library/Application Support/HandBrake/UserPresets.json`, and the bundled `Resources/YouTubeRenders.json`
  (both used with `--preset-import-file`). VideoToolbox presets are marked ⚡ on Apple Silicon.
- Async `--scan --json` per file (no timeout), language-based audio/subtitle selection (ISO 639-2 codes, e.g. `eng,spa`)
  via `--audio-lang-list/--all-audio` and `--subtitle-lang-list/--all-subtitles`.
- Progress from HandBrakeCLI `--json` output, with a regex fallback for the plain-text progress line.
- Queue with configurable concurrency (default 1 for software encoders, 2 for VideoToolbox), per-item cancel/retry,
  persisted to `~/Library/Application Support/HandBrake Batch/queue.json` and resumed after a crash.
- Output is written to a hidden temp file in the destination folder and atomically renamed when done.
- Optional timestamp preservation, notification on completion, and sleep when done (`pmset sleepnow`).
- Per-job logs in `~/Library/Logs/HandBrake Batch/`.

## Command-line test mode
The same binary can run the queue headlessly:

```sh
B="/Applications/HandBrake Batch.app/Contents/MacOS/HandBrake Batch"
"$B" --list-presets
"$B" --cli-test --preset "H.265 Apple VideoToolbox 1080p" --out ~/Movies --audio eng clip.mov
```

## The "YouTube Renders (StepByClick)" preset
From StepByClick, "Best HandBrake Settings for High Quality Output on PC (2026)" (https://www.youtube.com/watch?v=kjui8y6Utv0):

| Setting | Value | Source |
|---|---|---|
| Resolution | Same as source (no size limit, no upscaling) | video: "make sure the resolution is set to same as source" |
| Video encoder | H.264 (x264) | video: "Set the video codec to H.264" |
| Frame rate | Same as source, constant | video: "frame rate to same as source … constant frame rate" |
| Quality | RF 18 | video: "set it to 18" |
| Encoder preset | slow | video: "Set the encoder preset to slow" |
| Audio bitrate | 320 kbps | video: "audio bit rate is set to 320" |
| Container | MP4 | video: "file extension is set to MP4" |
| Audio codec AAC, stereo mixdown | inferred (video only names the bitrate) | |
| H.264 profile/level auto, filters, crop | inferred; everything else is from HandBrake's "HQ 1080p30 Surround" preset | |

## License
GPL-3.0, like the original HandBrakeBatch. See LICENSE.
