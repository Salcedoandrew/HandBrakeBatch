import SwiftUI

/// User-edited preset copies, stored in HandBrake preset JSON so --preset-import-file works.
enum EditedPresets {
    static var file: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HandBrake Batch/EditedPresets.json").path
    }
    static func list() -> [[String: Any]] {
        guard let d = FileManager.default.contents(atPath: file),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return o["PresetList"] as? [[String: Any]] ?? []
    }
    static func write(_ l: [[String: Any]]) {
        try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let o: [String: Any] = ["PresetList": l, "VersionMajor": 66, "VersionMinor": 0, "VersionMicro": 0]
        try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: file))
    }
    static func save(_ p: [String: Any]) { write(list().filter { $0["PresetName"] as? String != p["PresetName"] as? String } + [p]) }
    static func delete(_ name: String) { write(list().filter { $0["PresetName"] as? String != name }) }
    /// Full settings of any preset via `HandBrakeCLI --preset-export`.
    static func export(_ p: HBPreset) async -> [String: Any]? {
        let tmp = NSTemporaryDirectory() + "hbb-export.json"
        try? FileManager.default.removeItem(atPath: tmp)
        _ = await HandBrakeCLI.run((p.importFile.map { ["--preset-import-file", $0] } ?? []) + ["-Z", p.name, "--preset-export", p.name, "--preset-export-file", tmp])
        guard let d = FileManager.default.contents(atPath: tmp),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return (o["PresetList"] as? [[String: Any]])?.first
    }
}

struct PresetEditor: View {
    @State var p: [String: Any]
    var done: (Bool) -> Void
    func b<T>(_ k: String, _ d: T) -> Binding<T> { Binding(get: { p[k] as? T ?? d }, set: { p[k] = $0 }) }
    var bitrate: Binding<Int> { Binding(get: { (p["AudioList"] as? [[String: Any]])?.first?["AudioBitrate"] as? Int ?? 160 },
        set: { var a = p["AudioList"] as? [[String: Any]] ?? [[:]]; if a.isEmpty { a = [[:]] }; a[0]["AudioBitrate"] = $0; p["AudioList"] = a }) }
    var body: some View {
        Form {
            TextField("Name", text: b("PresetName", ""))
            Picker("Encoder", selection: b("VideoEncoder", "x264")) {
                ForEach(["x264", "x264_10bit", "x265", "x265_10bit", "vt_h264", "vt_h265", "vt_h265_10bit", "svt_av1", "VP9"], id: \.self) { Text($0) }
            }
            Stepper("RF \(Int(b("VideoQualitySlider", 22.0).wrappedValue))", value: b("VideoQualitySlider", 22.0), in: 0...51)
            TextField("Max width", value: b("PictureWidth", 1920), format: .number)
            TextField("Max height", value: b("PictureHeight", 1080), format: .number)
            Picker("Framerate", selection: b("VideoFramerate", "auto")) {
                ForEach(["auto", "23.976", "24", "25", "29.97", "30", "50", "59.94", "60"], id: \.self) { Text($0 == "auto" ? "Same as source" : $0) }
            }
            Picker("Audio kbps", selection: bitrate) { ForEach([96, 128, 160, 192, 256, 320], id: \.self) { Text("\($0)") } }
            Picker("Format", selection: b("FileFormat", "av_mp4")) { Text("MP4").tag("av_mp4"); Text("MKV").tag("av_mkv") }
            HStack { Button("Cancel") { done(false) }; Button("Save") { p["Type"] = 1; p["Default"] = false; EditedPresets.save(p); done(true) }.keyboardShortcut(.defaultAction) }
        }.padding().frame(width: 380)
    }
}
