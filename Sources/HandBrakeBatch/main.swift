import SwiftUI
import AppKit

struct HandBrakeBatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("HandBrake Batch") {
            ContentView(queue: model.queue).environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { Notifier.requestAuth(); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let args = CommandLine.arguments
if args.contains("--cli-test") || args.contains("--list-presets") {
    CLIMode.run(Array(args.dropFirst()))
} else {
    HandBrakeBatchApp.main()
}
