import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var queue: QueueManager
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            settings
            Divider()
            jobList
            footer
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
        .task { await model.load() }
    }

    private var groupedCategories: [String] {
        var seen: [String] = []
        for p in model.presets where !seen.contains(p.category) { seen.append(p.category) }
        return seen
    }

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("HandBrakeCLI")
                Text("\(model.version)  ·  \(Hardware.summary)").foregroundStyle(.secondary).font(.callout.monospaced())
            }
            GridRow {
                Text("Preset")
                HStack {
                    Picker("", selection: $model.selectedPresetID) {
                        ForEach(groupedCategories, id: \.self) { cat in
                            Section(cat) {
                                ForEach(model.presets.filter { $0.category == cat }) { p in
                                    Text(p.isVideoToolbox && Hardware.hasHardwareHEVC ? "⚡︎ \(p.name)" : p.name).tag(p.id)
                                }
                            }
                        }
                    }.labelsHidden().frame(maxWidth: 360)
                    if let p = model.selectedPreset, p.isVideoToolbox, Hardware.hasHardwareHEVC {
                        Text("VideoToolbox: hardware encode (\(Hardware.engineName))")
                            .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                    }
                }
            }
            GridRow {
                Text("Output")
                HStack {
                    Text(model.outputDir).lineLimit(1).truncationMode(.middle).frame(maxWidth: 360, alignment: .leading)
                    Button("Choose…") { chooseOutput() }
                    Picker("", selection: $model.outputExt) { Text("MP4").tag("mp4"); Text("M4V").tag("m4v"); Text("MKV").tag("mkv") }
                        .labelsHidden().frame(width: 80)
                }
            }
            GridRow {
                Text("Languages")
                HStack {
                    TextField("Audio, e.g. eng,spa", text: $model.audioLangs).frame(width: 170)
                    TextField("Subtitles, e.g. eng", text: $model.subtitleLangs).frame(width: 170)
                    Text("ISO 639-2 codes; matching original tracks are kept").font(.caption).foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("Options")
                HStack(spacing: 14) {
                    Toggle("Keep file dates", isOn: $model.preserveTimestamps)
                    Toggle("Notify", isOn: $model.notify)
                    Toggle("Sleep when done", isOn: $model.sleepWhenDone)
                    Stepper("Parallel jobs: \(queue.concurrency)", value: $queue.concurrency, in: 1...8)
                }
            }
        }
    }

    private var jobList: some View {
        List {
            if queue.jobs.isEmpty {
                Text("Drop video files or folders here").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
            ForEach(queue.jobs) { job in JobRow(job: job, queue: queue) }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(dropTargeted ? Color.accentColor : .clear, lineWidth: 2))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task {
                var urls: [URL] = []
                for p in providers {
                    if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                       let data = item as? Data, let u = URL(dataRepresentation: data, relativeTo: nil) { urls.append(u) }
                }
                await MainActor.run { model.add(urls: urls) }
            }
            return true
        }
    }

    private var footer: some View {
        HStack {
            Button("Add Files…") { addFiles() }
            Button("Clear Finished") { queue.clearFinished() }
            Spacer()
            if let summary = queue.batchSummary, !queue.processing { Text(summary).foregroundStyle(.secondary) }
            else { Text("\(queue.jobs.filter { $0.status == .done }.count)/\(queue.jobs.count) done").foregroundStyle(.secondary) }
            if queue.processing { Button("Pause Queue") { queue.stop() } }
            else { Button("Start") { queue.start() }.keyboardShortcut(.return).disabled(!queue.jobs.contains { $0.status == .pending }) }
        }
    }

    private func chooseOutput() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { model.outputDir = u.path }
    }
    private func addFiles() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true
        p.allowedContentTypes = [.movie, .folder]
        if p.runModal() == .OK { model.add(urls: p.urls) }
    }
}

struct JobRow: View {
    let job: Job
    @ObservedObject var queue: QueueManager
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(job.fileName).lineLimit(1)
                Text("\(job.preset.name) → \((job.output as NSString).lastPathComponent)\(job.status == .done ? "" : " · " + job.message)")
                    .font(.caption).foregroundStyle(job.status == .failed ? .red : .secondary).lineLimit(1)
            }
            Spacer()
            if job.status == .running { ProgressView(value: job.progress).frame(width: 120) }
            else if let saved = job.savingsText {
                Text(saved).font(.caption.monospacedDigit())
                    .foregroundStyle((job.outputBytes ?? 0) <= (job.inputBytes ?? 0) ? Color.green : Color.orange)
            }
            else { Text(job.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
            if job.status == .running || job.status == .pending {
                Button { queue.cancel(job.id) } label: { Image(systemName: "xmark.circle") }.help("Cancel")
            }
            if job.status == .failed || job.status == .cancelled || job.status == .done {
                Button { queue.retry(job.id) } label: { Image(systemName: "arrow.clockwise") }.help("Retry")
            }
            Button { NSWorkspace.shared.open(queue.logURL(job)) } label: { Image(systemName: "doc.text") }.help("Show log")
            Button { queue.remove(job.id) } label: { Image(systemName: "trash") }.help("Remove").disabled(job.status == .running)
        }.buttonStyle(.borderless)
    }
}
