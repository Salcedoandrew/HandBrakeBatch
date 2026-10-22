import Foundation

/// A preset that HandBrakeCLI can use via `-Z`, optionally imported from a JSON file.
struct HBPreset: Identifiable, Hashable, Codable {
    var name: String
    var category: String
    var importFile: String?   // passed with --preset-import-file
    var description: String = ""
    var id: String { (importFile ?? "builtin") + "|" + name }
    var isVideoToolbox: Bool { name.localizedCaseInsensitiveContains("VideoToolbox") || encoder.contains("vt_") }
    var encoder: String = ""
    var qualityType: Int? = nil   // VideoQualityType from JSON presets: 2 = constant quality
    var usesConstantQuality: Bool { qualityType == 2 }
}

struct ScanTrack: Hashable { var index: Int; var language: String; var description: String }
struct ScanResult { var duration: Double; var audio: [ScanTrack]; var subtitles: [ScanTrack]; var height: Int = 0 }

enum HandBrakeCLI {
    static var path: String? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["HANDBRAKECLI"], FileManager.default.isExecutableFile(atPath: p) { return p }
        var cands = ["/opt/homebrew/bin/HandBrakeCLI", "/usr/local/bin/HandBrakeCLI"]
        cands += (env["PATH"] ?? "").split(separator: ":").map { "\($0)/HandBrakeCLI" }
        return cands.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs the CLI to completion off the main thread; returns (stdout, stderr). No timeout.
    static func run(_ args: [String]) async -> (String, String) {
        guard let exe = path else { return ("", "HandBrakeCLI not found") }
        return await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.standardInput = FileHandle.nullDevice
            final class Box: @unchecked Sendable { var o = Data(), e = Data() }
            let box = Box()
            let g = DispatchGroup()
            g.enter(); g.enter()
            DispatchQueue.global().async { box.o = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
            DispatchQueue.global().async { box.e = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
            p.terminationHandler = { _ in
                g.notify(queue: .global()) {
                    cont.resume(returning: (String(decoding: box.o, as: UTF8.self), String(decoding: box.e, as: UTF8.self)))
                }
            }
            do { try p.run() } catch { cont.resume(returning: ("", "\(error)")) }
        }
    }

    static func version() async -> String {
        let (o, e) = await run(["--version"])
        return (o + "\n" + e).split(separator: "\n").map(String.init)
            .first { $0.hasPrefix("HandBrake ") } ?? "HandBrakeCLI not found"
    }

    /// Built-in presets parsed from `HandBrakeCLI --preset-list`.
    static func builtinPresets() async -> [HBPreset] {
        let (o, e) = await run(["--preset-list"])
        var result: [HBPreset] = []
        var category = ""
        for raw in (e + "\n" + o).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("[") || line.hasPrefix("HandBrake has exited") { continue }
            if !line.hasPrefix(" "), line.hasSuffix("/") { category = String(line.dropLast()); continue }
            if line.hasPrefix("        ") {
                if !result.isEmpty { result[result.count - 1].description += (result[result.count - 1].description.isEmpty ? "" : " ") + line.trimmingCharacters(in: .whitespaces) }
                continue
            }
            if line.hasPrefix("    "), !category.isEmpty {
                let name = line.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { result.append(HBPreset(name: name, category: category, importFile: nil)) }
            }
        }
        return result
    }

    /// Presets from a HandBrake JSON preset file (UserPresets.json or an exported preset).
    static func presets(fromFile path: String, category: String) -> [HBPreset] {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["PresetList"] as? [[String: Any]] else { return [] }
        var out: [HBPreset] = []
        func walk(_ items: [[String: Any]], _ cat: String) {
            for item in items {
                if (item["Folder"] as? Bool) == true {
                    walk(item["ChildrenArray"] as? [[String: Any]] ?? [], item["PresetName"] as? String ?? cat)
                } else if let n = item["PresetName"] as? String {
                    out.append(HBPreset(name: n, category: cat, importFile: path,
                                        description: item["PresetDescription"] as? String ?? "",
                                        encoder: item["VideoEncoder"] as? String ?? "",
                                        qualityType: item["VideoQualityType"] as? Int))
                }
            }
        }
        walk(list, category)
        return out
    }

    static func scan(_ file: String) async -> ScanResult? {
        let (o, _) = await run(["--scan", "--json", "-i", file, "-t", "1"])
        guard let r = o.range(of: "JSON Title Set:") else { return nil }
        let json = String(o[r.upperBound...])
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let title = (obj["TitleList"] as? [[String: Any]])?.first else { return nil }
        func tracks(_ key: String) -> [ScanTrack] {
            ((title[key] as? [[String: Any]]) ?? []).enumerated().map { i, t in
                ScanTrack(index: i + 1, language: (t["LanguageCode"] as? String) ?? "und",
                          description: (t["Description"] as? String) ?? "")
            }
        }
        var dur = 0.0
        if let d = title["Duration"] as? [String: Any] {
            let h: Int = d["Hours"] as? Int ?? 0
            let m: Int = d["Minutes"] as? Int ?? 0
            let sec: Int = d["Seconds"] as? Int ?? 0
            dur = Double(h * 3600 + m * 60 + sec)
        }
        let height = (title["Geometry"] as? [String: Any])?["Height"] as? Int ?? 0
        return ScanResult(duration: dur, audio: tracks("AudioList"), subtitles: tracks("SubtitleList"), height: height)
    }
}

/// Parses HandBrakeCLI `--json` progress blocks; falls back to the classic "Encoding: ... 12.34 %" text.
/// Multi-pass jobs report Pass/PassCount; `overall` combines all passes into one 0-100% value.
struct ProgressUpdate { var overall: Double; var pass: Int; var passCount: Int; var passProgress: Double }

struct ProgressParser {
    private var state = ""
    private var pass = 1, passCount = 1
    private static let stateRe = try! NSRegularExpression(pattern: #""State"\s*:\s*"(\w+)""#)
    private static let progRe = try! NSRegularExpression(pattern: #""Progress"\s*:\s*([0-9.eE+-]+)"#)
    private static let passRe = try! NSRegularExpression(pattern: #""Pass"\s*:\s*(\d+)"#)
    private static let passCountRe = try! NSRegularExpression(pattern: #""PassCount"\s*:\s*(\d+)"#)
    private static let textRe = try! NSRegularExpression(pattern: #"Encoding: task (\d+) of (\d+), ([0-9.]+) %"#)

    private static func last(_ re: NSRegularExpression, _ s: String, _ group: Int = 1) -> String? {
        let ns = s as NSString
        guard let m = re.matches(in: s, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    mutating func feed(_ s: String) -> ProgressUpdate? {
        if let st = Self.last(Self.stateRe, s) { state = st }
        var p: Double?
        if state == "WORKING" || state == "MUXING" {
            if let v = Self.last(Self.passRe, s).flatMap(Int.init) { pass = max(1, v) }
            if let v = Self.last(Self.passCountRe, s).flatMap(Int.init) { passCount = max(1, v) }
            p = Self.last(Self.progRe, s).flatMap(Double.init)
        }
        if p == nil, let v = Self.last(Self.textRe, s, 3).flatMap(Double.init) {
            if let t = Self.last(Self.textRe, s, 1).flatMap(Int.init) { pass = t }
            if let c = Self.last(Self.textRe, s, 2).flatMap(Int.init) { passCount = c }
            p = v / 100
        }
        guard let raw = p else { return nil }
        let pp = min(max(raw, 0), 1)
        let pc = max(passCount, 1), ps = min(max(pass, 1), pc)
        return ProgressUpdate(overall: (Double(ps - 1) + pp) / Double(pc), pass: ps, passCount: pc, passProgress: pp)
    }
}
