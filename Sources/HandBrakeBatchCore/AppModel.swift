import Foundation
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published var version = "Checking HandBrakeCLI…"
    @Published var presets: [HBPreset] = []
    @Published var selectedPresetID: String = "" { didSet { presetChanged() } }
    @AppStorage("outputDir") var outputDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies").path
    @AppStorage("outputExt") var outputExt = "mp4"
    @AppStorage("audioLangs") var audioLangs = "eng"
    @AppStorage("subtitleLangs") var subtitleLangs = ""
    @AppStorage("preserveTimestamps") var preserveTimestamps = true
    @AppStorage("notify") var notify = true { didSet { queue.notify = notify } }
    @AppStorage("sleepWhenDone") var sleepWhenDone = false { didSet { queue.sleepWhenDone = sleepWhenDone } }
    @AppStorage("lastPreset") var lastPreset = ""
    public let queue = QueueManager()
    var isAppleSilicon: Bool { Hardware.isAppleSilicon }

    var selectedPreset: HBPreset? { presets.first { $0.id == selectedPresetID } }

    public init() {
        queue.notify = notify; queue.sleepWhenDone = sleepWhenDone
        queue.restore()
    }

    static var customPresetFile: String? {
        if let u = Bundle.main.url(forResource: "YouTubeRenders", withExtension: "json") { return u.path }
        let alt = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("../Resources/YouTubeRenders.json").standardized.path
        return FileManager.default.fileExists(atPath: alt) ? alt : nil
    }
    static var userPresetFile: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HandBrake/UserPresets.json").path
    }

    static func loadAllPresets() async -> [HBPreset] {
        var all: [HBPreset] = []
        if let f = customPresetFile { all += HandBrakeCLI.presets(fromFile: f, category: "HandBrake Batch") }
        all += HandBrakeCLI.presets(fromFile: userPresetFile, category: "My Presets")
        all += await HandBrakeCLI.builtinPresets()
        return all
    }

    func load() async {
        version = await HandBrakeCLI.version()
        presets = await Self.loadAllPresets()
        let preferred = presets.first { $0.id == lastPreset }
            ?? Hardware.preferredPreset(in: presets)
            ?? presets.first
        selectedPresetID = preferred?.id ?? ""
    }

    private func presetChanged() {
        guard let p = selectedPreset else { return }
        lastPreset = p.id
        if !queue.processing { queue.concurrency = Hardware.defaultConcurrency(for: p) }
    }

    static func langs(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == " " }).map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    func add(urls: [URL]) {
        guard let preset = selectedPreset else { return }
        let exts: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "ts", "m2ts", "mts", "mpg", "mpeg", "wmv", "flv", "webm", "vob", "3gp"]
        var files: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue, let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil) {
                for case let f as URL in e where exts.contains(f.pathExtension.lowercased()) { files.append(f) }
            } else { files.append(u) }
        }
        for f in files {
            queue.add(Job(input: f.path, output: Self.outputPath(for: f.path, dir: outputDir, ext: outputExt, reserved: Set(queue.jobs.filter { $0.status != .done }.map(\.output))), preset: preset,
                          audioLanguages: Self.langs(audioLangs), subtitleLanguages: Self.langs(subtitleLangs),
                          preserveTimestamps: preserveTimestamps))
        }
    }

    static func outputPath(for input: String, dir: String, ext: String, reserved: Set<String> = []) -> String {
        let base = ((input as NSString).lastPathComponent as NSString).deletingPathExtension
        var candidate = (dir as NSString).appendingPathComponent("\(base).\(ext)")
        var n = 1
        while FileManager.default.fileExists(atPath: candidate) || candidate == input || reserved.contains(candidate) {
            candidate = (dir as NSString).appendingPathComponent("\(base) (\(n)).\(ext)"); n += 1
        }
        return candidate
    }
}
