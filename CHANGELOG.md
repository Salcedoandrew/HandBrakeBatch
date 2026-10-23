# Changelog

## 1.3.0 (2026-10-22)

- HandBrake Batch now comes with HandBrake's own command-line encoder (HandBrakeCLI 1.11.2) built in, so a new Mac no longer needs Homebrew or a separate HandBrakeCLI install. Just drag the app to Applications.
- The bundled copy is the official, unmodified universal build from HandBrake (it runs natively on Apple Silicon and Intel). It is used first. If it is ever missing, the app still falls back to a HandBrakeCLI from Homebrew.
- The window (next to "HandBrakeCLI") and the command-line test mode now show which copy is in use, for example "HandBrake 1.11.2 (bundled)" or the path of the Homebrew copy.
- The app is bigger now (about 114 MB instead of 1.4 MB) because it carries the encoder. HandBrake's GPL-2 license text is included inside the app.

## 1.2.2 (2026-10-22)

- On Intel Macs, the "YouTube Renders – Fast (Hardware)" preset now encodes in one pass instead of two, so each file is only processed once. It uses about 9.5 Mbps for 1080p video, and more for 1440p and 4K. Apple Silicon Macs are unchanged.
- For any job that does run in two passes, the progress bar now goes from 0 to 100% once for the whole job, and the row says "Pass 1 of 2 (analysis)" or "Pass 2 of 2".
- Added a DMG installer to the release.

## 1.2.1 (2026-10-22)

- New app icon.

## 1.2.0 (2026-10-22)

- The "YouTube Renders (StepByClick)" preset is now about 1.4 times faster. It uses x264's "medium" speed setting instead of "slow". In testing the files were the same size and looked the same. All other settings are unchanged.
- New preset "YouTube Renders – Fast (Hardware)". It uses the Mac's built-in hardware video encoder, so it is much faster and makes smaller files. Quality is close to the regular preset, but the regular one is still better for very detailed or grainy video.
- Each finished file now shows how much space it saved, for example "Saved 1.2 GB (64%)", or "Grew by …" if the new file is bigger.
- When a batch finishes, the window and the notification show a total, for example "Batch done: 12 files, saved 8.4 GB (58%)".
- Fixed: adding two files with the same name no longer makes them write to the same output file.

## 1.1.0 (2026-10-22)

Tuned for Intel Macs as well as Apple Silicon, still as one app that runs on both.

- The app now checks at startup whether it is on an Apple Silicon or Intel Mac and whether the Mac can encode HEVC video in hardware.
- On Intel Macs that support it (such as the 2018 15-inch MacBook Pro), the hardware VideoToolbox H.265 preset is now chosen by default, just like on Apple Silicon, and is marked with ⚡.
- By default, hardware (VideoToolbox) encodes run two at a time and software (x264/x265) encodes run one at a time, because software encoding already uses every CPU core. You can still change this.
- The window now shows the kind of Mac, its CPU cores and threads, and whether hardware HEVC encoding is available.
- On the 2018 MacBook Pro, running two hardware encodes at once is faster than one at a time: macOS sends one to the T2 chip's video encoder and the other to Intel Quick Sync. So two stays the default there.

## 1.0.0 (2026-10-22)

First release of the native rewrite of HandBrakeBatch.

- Rewritten from scratch in Swift and SwiftUI. Runs natively on Apple Silicon and Intel Macs (universal app).
- Uses the HandBrakeCLI you already have installed (for example from Homebrew) and shows its version in the window. No old bundled copy of HandBrake.
- Lists all of HandBrake's current built-in presets, plus your own presets from the HandBrake app if you have any. Apple VideoToolbox (hardware) presets are marked with ⚡ on Apple Silicon.
- Adds a "YouTube Renders (StepByClick)" preset based on the settings recommended in a StepByClick video tutorial.
- Drag video files or whole folders onto the window to add them.
- Keeps only the audio and subtitle tracks in the languages you choose.
- Can keep the original file's created and modified dates on the converted file.
- Shows a notification when the batch is done and can put the Mac to sleep afterward.
- Runs one job at a time for software encoding and two at a time for hardware encoding by default; you can change this.
- Cancel, retry, or remove each job. The queue is saved, so if the app quits or crashes it picks up where it left off.
- Files are written under a hidden temporary name and only renamed once finished, so you never get a half-written video.
- Each job writes its own log to ~/Library/Logs/HandBrake Batch/.
- Removed EyeTV support and the Sparkle auto-updater.
