import Foundation

/// Headless mode that drives the same QueueManager the GUI uses.
/// HandBrake\ Batch --list-presets
/// HandBrake\ Batch --cli-test --preset "<name>" [--out DIR] [--audio eng] [--subs eng] FILE...
enum CLIMode {
    static func run(_ argv: [String]) -> Never {
        var presetName = "", outDir: String?, audio = "", subs = "", files: [String] = []
        var i = 0
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "--preset": i += 1; presetName = argv[i]
            case "--out": i += 1; outDir = argv[i]
            case "--audio": i += 1; audio = argv[i]
            case "--subs": i += 1; subs = argv[i]
            case "--cli-test", "--list-presets": break
            default: files.append(URL(fileURLWithPath: a).standardizedFileURL.path)
            }
            i += 1
        }
        let cfg = (presetName, outDir, audio, subs, files)
        Task { @MainActor in
            let (presetName, outDir, audio, subs, files) = cfg
            print(await HandBrakeCLI.version()); print(Hardware.summary + " · " + Hardware.cpuName)
            let presets = await AppModel.loadAllPresets()
            if argv.contains("--list-presets") {
                for p in presets { print("[\(p.category)] \(p.name)\(p.isVideoToolbox ? "  (VideoToolbox)" : "")") }
                exit(0)
            }
            guard let preset = presets.first(where: { $0.name == presetName }) else { print("Preset not found: \(presetName)"); exit(2) }
            let state = FileManager.default.temporaryDirectory.appendingPathComponent("hbb-cli-\(UUID().uuidString).json")
            let q = QueueManager(stateFile: state)
            q.notify = false
            q.concurrency = Hardware.defaultConcurrency(for: preset)
            for f in files {
                let dir = outDir ?? (f as NSString).deletingLastPathComponent
                q.add(Job(input: f, output: AppModel.outputPath(for: f, dir: dir, ext: "mp4", reserved: Set(q.jobs.map(\.output))), preset: preset,
                          audioLanguages: AppModel.langs(audio), subtitleLanguages: AppModel.langs(subs), preserveTimestamps: true))
            }
            var last = -1
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    let pct = Int((q.jobs.map(\.progress).reduce(0, +) / Double(max(q.jobs.count, 1))) * 100)
                    if pct / 10 != last / 10 { print("progress \(pct)%"); last = pct }
                }
            }
            q.onAllFinished = {
                timer.invalidate()
                for j in q.jobs { print("\(j.status.rawValue): \(j.fileName) -> \(j.output) [\(j.message)] log: \(q.logURL(j).path)") }
                if let s = q.batchSummary { print(s) }
                try? FileManager.default.removeItem(at: state)
                exit(q.jobs.allSatisfy { $0.status == .done } ? 0 : 1)
            }
            print("concurrency \(q.concurrency), preset \(preset.name)")
            q.start()
        }
        RunLoop.main.run()
        exit(0)
    }
}
