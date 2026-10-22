# Changelog

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
