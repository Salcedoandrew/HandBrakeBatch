import Foundation
import XCTest

@testable import HandBrakeBatchCore

final class HandBrakeBatchTests: XCTestCase {

    // MARK: - ProgressParser

    func testProgressParserJSONSinglePass() {
        var parser = ProgressParser()
        let update = parser.feed(#"{"State": "WORKING", "Progress": 0.5}"#)
        XCTAssertNotNil(update)
        XCTAssertEqual(update?.overall ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(update?.pass, 1)
        XCTAssertEqual(update?.passCount, 1)
        XCTAssertEqual(update?.passProgress ?? -1, 0.5, accuracy: 0.0001)
    }

    func testProgressParserJSONMuxingState() {
        var parser = ProgressParser()
        let update = parser.feed(#"{"State": "MUXING", "Progress": 0.9}"#)
        XCTAssertEqual(update?.overall ?? -1, 0.9, accuracy: 0.0001)
    }

    func testProgressParserJSONMultiPassCombinesPasses() {
        var parser = ProgressParser()
        let update = parser.feed(#"{"State": "WORKING", "Pass": 2, "PassCount": 2, "Progress": 0.25}"#)
        XCTAssertEqual(update?.overall ?? -1, 0.625, accuracy: 0.0001)
        XCTAssertEqual(update?.pass, 2)
        XCTAssertEqual(update?.passCount, 2)
        XCTAssertEqual(update?.passProgress ?? -1, 0.25, accuracy: 0.0001)
    }

    func testProgressParserTextFallback() {
        var parser = ProgressParser()
        let update = parser.feed("Encoding: task 1 of 2, 50.00 %")
        XCTAssertEqual(update?.overall ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(update?.pass, 1)
        XCTAssertEqual(update?.passCount, 2)
        XCTAssertEqual(update?.passProgress ?? -1, 0.5, accuracy: 0.0001)
    }

    func testProgressParserClampsAndIgnoresNoise() {
        var parser = ProgressParser()
        XCTAssertNil(parser.feed("nothing to see here"))
        let update = parser.feed(#"{"State": "WORKING", "Progress": 1.5}"#)
        XCTAssertEqual(update?.overall ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(update?.passProgress ?? -1, 1.0, accuracy: 0.0001)
    }

    // MARK: - Savings

    func testSavingsTextSaved() {
        let text = Savings.text(input: 1000, output: 400)
        XCTAssertTrue(text.hasPrefix("Saved "))
        XCTAssertTrue(text.hasSuffix("(60%)"))
    }

    func testSavingsTextGrew() {
        let text = Savings.text(input: 400, output: 1000)
        XCTAssertTrue(text.hasPrefix("Grew by "))
        XCTAssertTrue(text.hasSuffix("(150%)"))
    }

    func testSavingsTextZeroInputDoesNotCrash() {
        let text = Savings.text(input: 0, output: 0)
        XCTAssertTrue(text.hasSuffix("(0%)"))
    }

    // MARK: - QueueManager.arguments

    private func makeJob(output: String = "/tmp/out.mp4",
                         preset: HBPreset = HBPreset(name: "Preset", category: "Cat"),
                         audio: [String] = [],
                         subtitles: [String] = []) -> Job {
        Job(input: "/tmp/in.mov", output: output, preset: preset,
            audioLanguages: audio, subtitleLanguages: subtitles,
            preserveTimestamps: false)
    }

    func testArgumentsMP4Defaults() {
        let args = QueueManager.arguments(for: makeJob(), scan: nil)
        XCTAssertEqual(args[0], "-Z")
        XCTAssertEqual(args[1], "Preset")
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/in.mov"))
        XCTAssertTrue(args.contains("--json"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertEqual(args[args.firstIndex(of: "-f")! + 1], "av_mp4")
        let outIndex = args.firstIndex(of: "-o")!
        XCTAssertTrue(args[outIndex + 1].hasSuffix(".hbbpart"))
    }

    func testArgumentsContainerFormats() {
        let mkv = QueueManager.arguments(for: makeJob(output: "/tmp/out.mkv"), scan: nil)
        XCTAssertEqual(mkv[mkv.firstIndex(of: "-f")! + 1], "av_mkv")
        let webm = QueueManager.arguments(for: makeJob(output: "/tmp/out.webm"), scan: nil)
        XCTAssertEqual(webm[webm.firstIndex(of: "-f")! + 1], "av_webm")
    }

    func testArgumentsPresetImportFile() {
        let preset = HBPreset(name: "Custom", category: "Mine", importFile: "/tmp/presets.json")
        let args = QueueManager.arguments(for: makeJob(preset: preset), scan: nil)
        XCTAssertEqual(args[0], "--preset-import-file")
        XCTAssertEqual(args[1], "/tmp/presets.json")
        XCTAssertEqual(args[2], "-Z")
        XCTAssertEqual(args[3], "Custom")
    }

    func testArgumentsLanguageLists() {
        let scan = ScanResult(duration: 60, audio: [], subtitles: [ScanTrack(index: 1, language: "spa", description: "")], height: 1080)
        let args = QueueManager.arguments(for: makeJob(audio: ["eng", "spa"], subtitles: ["spa"]), scan: scan)
        XCTAssertTrue(args.contains("--audio-lang-list"))
        XCTAssertEqual(args[args.firstIndex(of: "--audio-lang-list")! + 1], "eng,spa")
        XCTAssertTrue(args.contains("--all-audio"))
        XCTAssertTrue(args.contains("--subtitle-lang-list"))
        XCTAssertEqual(args[args.firstIndex(of: "--subtitle-lang-list")! + 1], "spa")
        XCTAssertTrue(args.contains("--all-subtitles"))
    }

    func testArgumentsSubtitleNoneWhenNoMatchingTrack() {
        let scan = ScanResult(duration: 60, audio: [], subtitles: [ScanTrack(index: 1, language: "fre", description: "")], height: 1080)
        let args = QueueManager.arguments(for: makeJob(subtitles: ["spa"]), scan: scan)
        XCTAssertTrue(args.contains("-s"))
        XCTAssertEqual(args[args.firstIndex(of: "-s")! + 1], "none")
        XCTAssertFalse(args.contains("--subtitle-lang-list"))
    }

    // MARK: - Preset file parsing

    func testPresetsFromFile() throws {
        let json = #"{"PresetList": [{"PresetName": "Group", "Folder": true, "ChildrenArray": [{"PresetName": "Child", "PresetDescription": "d", "VideoEncoder": "x264", "VideoQualityType": 2}]}, {"PresetName": "Solo", "PresetDescription": "", "VideoEncoder": "vt_h265", "VideoQualityType": 1}]}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hbb-test-presets-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let presets = HandBrakeCLI.presets(fromFile: url.path, category: "Mine")
        XCTAssertEqual(presets.count, 2)
        XCTAssertEqual(presets[0].name, "Child")
        XCTAssertEqual(presets[0].category, "Group")
        XCTAssertEqual(presets[0].encoder, "x264")
        XCTAssertTrue(presets[0].usesConstantQuality)
        XCTAssertEqual(presets[1].name, "Solo")
        XCTAssertEqual(presets[1].category, "Mine")
        XCTAssertEqual(presets[1].encoder, "vt_h265")
        XCTAssertFalse(presets[1].usesConstantQuality)
        XCTAssertTrue(presets[1].isVideoToolbox)
    }

    func testPresetsFromMissingFileIsEmpty() {
        XCTAssertTrue(HandBrakeCLI.presets(fromFile: "/tmp/does-not-exist-hbb.json", category: "Mine").isEmpty)
    }

    // MARK: - Hardware

    func testIntelVTBitrate() {
        XCTAssertEqual(Hardware.intelVTBitrate(height: 2160), 35000)
        XCTAssertEqual(Hardware.intelVTBitrate(height: 1440), 18000)
        XCTAssertEqual(Hardware.intelVTBitrate(height: 1080), 9500)
        XCTAssertEqual(Hardware.intelVTBitrate(height: 0), 9500)
        XCTAssertEqual(Hardware.intelVTBitrate(height: 720), 5000)
    }

    // MARK: - AppModel helpers

    func testLangs() {
        XCTAssertEqual(AppModel.langs("eng, spa"), ["eng", "spa"])
        XCTAssertEqual(AppModel.langs("ENG"), ["eng"])
        XCTAssertEqual(AppModel.langs(""), [])
    }

    func testOutputPathAvoidsCollisions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hbb-test-out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(
            AppModel.outputPath(for: dir.appendingPathComponent("clip.mov").path, dir: dir.path, ext: "mp4"),
            dir.appendingPathComponent("clip.mp4").path)
        XCTAssertEqual(
            AppModel.outputPath(for: dir.appendingPathComponent("clip.mov").path, dir: dir.path, ext: "mp4",
                                reserved: [dir.appendingPathComponent("clip.mp4").path]),
            dir.appendingPathComponent("clip (1).mp4").path)
        // Same name and extension as the input: never overwrite the source.
        XCTAssertEqual(
            AppModel.outputPath(for: dir.appendingPathComponent("clip.mp4").path, dir: dir.path, ext: "mp4"),
            dir.appendingPathComponent("clip (1).mp4").path)
    }
}
