<p align="center"><img src="assets/logo.png" alt="HandBrake Batch" width="256"></p>

# HandBrake Batch

Maintained and rewritten by Andrew Salcedo ([github.com/Salcedoandrew](https://github.com/Salcedoandrew)).
The original HandBrakeBatch by Cesare Tagliaferri ([taglia/handbrakebatch](https://github.com/taglia/handbrakebatch)) is no longer maintained.

A native macOS (Swift/SwiftUI) rewrite of [HandBrakeBatch](https://github.com/taglia/handbrakebatch): drop a pile of videos on the window and convert them all with HandBrake.

## Requirements
- macOS 13 or later (universal: Apple Silicon + Intel)
- Nothing else: since 1.3.0 the app ships with the official HandBrakeCLI (1.11.2, universal) inside
  `Contents/Resources/bin/`, so you no longer need Homebrew or `brew install handbrake`. If the bundled copy is missing,
  it falls back to /opt/homebrew/bin, /usr/local/bin, or `$PATH`; `$HANDBRAKECLI` overrides everything.
  The copy in use is shown in the window, e.g. "HandBrake 1.11.2 (bundled)".

## Build and install
Only the Xcode Command Line Tools are needed.

```sh
./build.sh            # builds build/HandBrake Batch.app (ad-hoc signed)
./build.sh --install  # also copies it to /Applications
./build.sh --dmg      # also makes build/HandBrake-Batch-<version>-universal.dmg
```
`build.sh` downloads HandBrakeCLI-1.11.2.dmg from HandBrake's GitHub release once, checks its SHA-256 against the
official one, caches it in `.cache/` (not in git), and copies the binary plus HandBrake's license (GPL-2.0) into the app.

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
| Encoder preset | medium (the video says slow) | changed in 1.2.0 for speed, see below |
| Audio bitrate | 320 kbps | video: "audio bit rate is set to 320" |
| Container | MP4 | video: "file extension is set to MP4" |
| Audio codec AAC, stereo mixdown | inferred (video only names the bitrate) | |
| H.264 profile/level auto, filters, crop | inferred; everything else is from HandBrake's "HQ 1080p30 Surround" preset | |

### Speed vs. quality (v1.2.0)
Measured on the M1 Pro with a generated 30-second 1080p30 clip (synthetic, with light grain; real footage will differ).
PSNR-Y is against the source, higher is better.

| Encoder | Speed | Size | PSNR-Y |
|---|---|---|---|
| x264 slow (the video's choice) | ~35 fps | 20 MB | 51.3 dB |
| **x264 medium (new default)** | ~48 fps | 20 MB | 51.2 dB |
| x264 fast | ~55 fps | 23 MB | 51.5 dB |
| x264 faster | ~72 fps | 21 MB | 51.7 dB |
| **VideoToolbox H.264, quality 70 ("Fast (Hardware)")** | ~90 fps (source decode bound) | 7 MB | 51.1 dB |
| VideoToolbox H.264, quality 65 | ~87 fps | 5 MB | 50.5 dB |

- "YouTube Renders (StepByClick)" now uses x264 **medium**: about 1.4x faster than slow for the same file size and
  practically the same quality. Everything else (RF 18, source resolution and frame rate, MP4, 320 kbps AAC) is unchanged.
- "YouTube Renders – Fast (Hardware)" uses the Mac's hardware H.264 encoder (VideoToolbox) at constant quality 70.
  It is the fastest option on both Macs and the files are smaller. The tradeoff: hardware encoders are less efficient than
  x264 on difficult footage (fine detail, grain, fast motion), so pick the x264 preset when quality matters most.
- On Intel Macs, VideoToolbox does not support constant quality, so HandBrake falls back to a 9 Mbps average bitrate
  (two passes) on Intel Quick Sync. On the 2018 MacBook Pro this ran at ~50 fps vs ~30 fps for x264 medium on a 1080p clip.

## Troubleshooting

**"HandBrakeCLI not found" in the window.** The app couldn't find an
encoder. The copy bundled inside the app is tried first, then
`/opt/homebrew/bin`, `/usr/local/bin`, and `$PATH`; `$HANDBRAKECLI`
overrides everything. Rebuilding with `./build.sh` re-bundles the
official copy, or install one with `brew install handbrake`, or point
`$HANDBRAKECLI` at the copy you want.

**macOS blocks the app on first launch.** The app is ad-hoc signed,
not signed with an Apple Developer ID. Right-click it and choose
**Open**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/HandBrake Batch.app"
```

**The app quit or crashed mid-batch.** The queue is saved to
`~/Library/Application Support/HandBrake Batch/queue.json`, so
reopening the app resumes where it left off: interrupted jobs go back
to pending and their partial files are removed. Each job writes its
own log to `~/Library/Logs/HandBrake Batch/` — check the log for the
failed job first.

## License
GPL-3.0, like the original HandBrakeBatch. See LICENSE. The bundled HandBrakeCLI is HandBrake's own unmodified build, licensed GPL-2.0
(its COPYING, LICENSE, and source location are in `Contents/Resources/HandBrakeCLI-license/`).
