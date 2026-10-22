import Foundation
import UserNotifications

enum JobStatus: String, Codable { case pending, running, done, failed, cancelled }

struct Job: Identifiable, Codable, Equatable {
    var id = UUID()
    var input: String
    var output: String
    var preset: HBPreset
    var audioLanguages: [String]
    var subtitleLanguages: [String]
    var preserveTimestamps: Bool
    var status: JobStatus = .pending
    var progress: Double = 0
    var message: String = ""
    var attempts: Int = 0
    var inputBytes: Int64?
    var outputBytes: Int64?
    /// "Saved 1.2 GB (64%)" or "Grew by 10 MB (5%)" once the job is done.
    var savingsText: String? {
        guard status == .done, let i = inputBytes, let o = outputBytes else { return nil }
        return Savings.text(input: i, output: o)
    }
    var fileName: String { (input as NSString).lastPathComponent }
    var tempOutput: String {
        let dir = (output as NSString).deletingLastPathComponent
        let name = (output as NSString).lastPathComponent
        return (dir as NSString).appendingPathComponent(".\(name).\(id.uuidString.prefix(8)).hbbpart")
    }
    static func == (a: Job, b: Job) -> Bool { a.id == b.id && a.status == b.status && a.progress == b.progress && a.message == b.message }
}

enum Savings {
    static func format(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; return f.string(fromByteCount: b)
    }
    static func text(input: Int64, output: Int64) -> String {
        let diff = input - output
        let pct = input > 0 ? Int((Double(abs(diff)) / Double(input) * 100).rounded()) : 0
        return diff >= 0 ? "Saved \(format(diff)) (\(pct)%)" : "Grew by \(format(-diff)) (\(pct)%)"
    }
}

struct QueueSnapshot: Codable { var jobs: [Job]; var processing: Bool; var concurrency: Int }

@MainActor
final class QueueManager: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var processing = false
    @Published var concurrency = 1
    var sleepWhenDone = false
    var notify = true
    var onAllFinished: (() -> Void)?

    private var running: [UUID: Process] = [:]
    private var cancelled: Set<UUID> = []
    let stateFile: URL
    static let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/HandBrake Batch", isDirectory: true)

    init(stateFile: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HandBrake Batch", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.logDir, withIntermediateDirectories: true)
        self.stateFile = stateFile ?? support.appendingPathComponent("queue.json")
    }

    /// Restores the queue after a quit or crash. Interrupted jobs go back to pending and their partial file is removed.
    func restore() {
        guard let data = try? Data(contentsOf: stateFile),
              let snap = try? JSONDecoder().decode(QueueSnapshot.self, from: data) else { return }
        jobs = snap.jobs.map { j in
            var j = j
            if j.status == .running {
                try? FileManager.default.removeItem(atPath: j.tempOutput)
                j.status = .pending; j.progress = 0; j.message = "Resumed after interruption"
            }
            return j
        }
        concurrency = max(1, snap.concurrency)
        if snap.processing && jobs.contains(where: { $0.status == .pending }) { start() }
    }

    func save() {
        let snap = QueueSnapshot(jobs: jobs, processing: processing, concurrency: concurrency)
        if let d = try? JSONEncoder().encode(snap) { try? d.write(to: stateFile, options: .atomic) }
    }

    func add(_ job: Job) { jobs.append(job); save(); if processing { pump() } }
    func remove(_ id: UUID) { cancel(id); jobs.removeAll { $0.id == id }; save() }
    func clearFinished() { jobs.removeAll { $0.status == .done }; save() }

    func start() { processing = true; save(); pump() }
    func stop() { processing = false; save() }

    func cancel(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        if jobs[i].status == .running { cancelled.insert(id); running[id]?.terminate() }
        else if jobs[i].status == .pending { jobs[i].status = .cancelled }
        save()
    }

    func retry(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].status != .running else { return }
        jobs[i].status = .pending; jobs[i].progress = 0; jobs[i].message = ""
        save(); if processing { pump() }
    }

    func logURL(_ job: Job) -> URL { Self.logDir.appendingPathComponent("\(job.fileName)-\(job.id.uuidString.prefix(8)).log") }

    private func pump() {
        guard processing else { return }
        while jobs.filter({ $0.status == .running }).count < concurrency, let i = jobs.firstIndex(where: { $0.status == .pending }) {
            launch(i)
        }
        if !jobs.contains(where: { $0.status == .pending || $0.status == .running }) {
            processing = false; save(); finishedAll()
        }
    }

    private func launch(_ i: Int) {
        let job = jobs[i]
        jobs[i].status = .running; jobs[i].progress = 0; jobs[i].attempts += 1; jobs[i].message = "Scanning…"
        save()
        Task { await self.encode(job) }
    }

    /// Builds the HandBrakeCLI argument array (never a shell string).
    nonisolated static func arguments(for job: Job, scan: ScanResult?) -> [String] {
        var a: [String] = []
        if let f = job.preset.importFile { a += ["--preset-import-file", f] }
        a += ["-Z", job.preset.name, "-i", job.input, "-o", job.tempOutput, "--json"]
        let ext = (job.output as NSString).pathExtension.lowercased()
        a += ["-f", ext == "mkv" ? "av_mkv" : (ext == "webm" ? "av_webm" : "av_mp4")]
        // Language-based track selection: keep every original track whose language matches.
        // Uses HandBrake's language lists so the preset's per-track encoder settings are kept
        // (an explicit -a list makes HandBrake fall back to default audio bitrates).
        if !job.audioLanguages.isEmpty {
            a += ["--audio-lang-list", job.audioLanguages.joined(separator: ","), "--all-audio"]
        }
        if !job.subtitleLanguages.isEmpty {
            if let scan, !scan.subtitles.contains(where: { job.subtitleLanguages.contains($0.language) }) {
                a += ["-s", "none"]
            } else {
                a += ["--subtitle-lang-list", job.subtitleLanguages.joined(separator: ","), "--all-subtitles"]
            }
        }
        return a
    }

    private func encode(_ job: Job) async {
        let scan = await HandBrakeCLI.scan(job.input)
        if cancelled.remove(job.id) != nil { finish(job, ok: false, msg: "Cancelled", status: .cancelled); return }
        guard let exe = HandBrakeCLI.path else { finish(job, ok: false, msg: "HandBrakeCLI not found"); return }
        let args = Self.arguments(for: job, scan: scan)
        let logURL = logURL(job)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)
        log?.seekToEndOfFile()
        log?.write(Data("$ \(exe) \(args.map { "'\($0)'" }.joined(separator: " "))\n".utf8))

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        var parser = ProgressParser()
        let id = job.id
        let lock = NSLock()
        let mgr = self
        let handler: (FileHandle) -> Void = { h in
            let d = h.availableData
            guard !d.isEmpty else { h.readabilityHandler = nil; return }
            lock.lock(); log?.write(d)
            let prog = parser.feed(String(decoding: d, as: UTF8.self)); lock.unlock()
            if let prog { Task { @MainActor in mgr.setProgress(id, prog) } }
        }
        out.fileHandleForReading.readabilityHandler = handler
        err.fileHandleForReading.readabilityHandler = handler
        p.terminationHandler = { proc in
            let code = proc.terminationStatus
            Task { @MainActor in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                log?.write(Data("\n[exit \(code)]\n".utf8)); try? log?.close()
                mgr.completed(job, code: code)
            }
        }
        do { try p.run(); running[id] = p; setMessage(id, "Encoding") }
        catch { finish(job, ok: false, msg: "Launch failed: \(error.localizedDescription)") }
    }

    private func completed(_ job: Job, code: Int32) {
        running[job.id] = nil
        let fm = FileManager.default
        if cancelled.remove(job.id) != nil {
            try? fm.removeItem(atPath: job.tempOutput); finish(job, ok: false, msg: "Cancelled", status: .cancelled); return
        }
        guard code == 0, fm.fileExists(atPath: job.tempOutput) else {
            try? fm.removeItem(atPath: job.tempOutput); finish(job, ok: false, msg: "HandBrakeCLI exited with \(code)"); return
        }
        // Atomic rename of the hidden temp file into place.
        if rename(job.tempOutput, job.output) != 0 {
            finish(job, ok: false, msg: "Rename failed: \(String(cString: strerror(errno)))"); return
        }
        if job.preserveTimestamps, let attrs = try? fm.attributesOfItem(atPath: job.input) {
            var keep: [FileAttributeKey: Any] = [:]
            keep[.creationDate] = attrs[.creationDate]; keep[.modificationDate] = attrs[.modificationDate]
            try? fm.setAttributes(keep, ofItemAtPath: job.output)
        }
        let inBytes = (try? fm.attributesOfItem(atPath: job.input)[.size] as? NSNumber)?.int64Value
        let outBytes = (try? fm.attributesOfItem(atPath: job.output)[.size] as? NSNumber)?.int64Value
        if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i].inputBytes = inBytes; jobs[i].outputBytes = outBytes }
        var msg = "Done"
        if let a = inBytes, let b = outBytes { msg = Savings.text(input: a, output: b) }
        finish(job, ok: true, msg: msg)
    }

    /// "Batch done: 12 files, saved 8.4 GB (58%)" over the finished jobs in the queue.
    var batchSummary: String? {
        let done = jobs.filter { $0.status == .done && $0.inputBytes != nil && $0.outputBytes != nil }
        guard !done.isEmpty else { return nil }
        let i = done.reduce(Int64(0)) { $0 + $1.inputBytes! }, o = done.reduce(Int64(0)) { $0 + $1.outputBytes! }
        let failed = jobs.filter { $0.status == .failed }.count
        let s = Savings.text(input: i, output: o)
        return "Batch done: \(done.count) file\(done.count == 1 ? "" : "s"), \(s.prefix(1).lowercased() + s.dropFirst())"
            + (failed > 0 ? ", \(failed) failed" : "")
    }

    private func finish(_ job: Job, ok: Bool, msg: String, status: JobStatus? = nil) {
        running[job.id] = nil
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[i].status = status ?? (ok ? .done : .failed)
            if ok { jobs[i].progress = 1 }
            jobs[i].message = msg
        }
        save(); pump()
    }

    private func setProgress(_ id: UUID, _ v: Double) {
        if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].status == .running {
            jobs[i].progress = v; jobs[i].message = String(format: "Encoding %.1f%%", v * 100)
        }
    }
    private func setMessage(_ id: UUID, _ m: String) { if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].message = m } }

    private func finishedAll() {
        let failed = jobs.filter { $0.status == .failed }.count
        if notify { Notifier.post("HandBrake Batch finished", batchSummary ?? "\(failed) failed") }
        onAllFinished?()
        if sleepWhenDone {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["sleepnow"]
            try? p.run()
        }
    }
}

enum Notifier {
    static func requestAuth() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func post(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
