import AppKit
import MacBuddyCore

/// Compiled with the actual app views/controller. Real telemetry, disposable
/// history/preferences, no stack logging and no access to the personal archive.
@main struct OverlayUICheck {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        let suite = "app.macbuddy.overlay-ui-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.register(defaults: ["displayMode":"Always visible", "notifications":false, "hasLaunched":true, "samplingMode":"Adaptive"])
        var preferences = OverlayPreferences(); preferences.backgroundOpacity = 0.60
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber
        let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)!.takeRetainedValue()
        preferences.floatingPosition = .init(screenID: CFUUIDCreateString(nil, uuid) as String, horizontal: 0.5, vertical: 0.25)
        preferences.save(to: defaults)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("MacBuddy-UI-" + Bundle.main.bundleIdentifier!)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let archive = scratch.appendingPathComponent("history.sqlite")
        let service = SamplingService(historyURL: archive)
        let model = MonitorModel(defaults: defaults, service: service)
        let delegate = AppDelegate(model: model)
        app.delegate = delegate
        let cleanup = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            defaults.removePersistentDomain(forName: suite)
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now()+2, repeating: 2)
        timer.setEventHandler {
            let windows = app.windows.filter { $0.isVisible }.map { window -> [String:Any] in
                ["title":window.title,"key":window.isKeyWindow,"canBecomeKey":window.canBecomeKey,
                 "x":window.frame.minX,"y":window.frame.minY,"width":window.frame.width,"height":window.frame.height]
            }
            var status: [String:Any] = ["sampleTimestamp":model.sample.timestamp.timeIntervalSince1970,
                "cpu":model.sample[.cpu] as Any? ?? NSNull(),"gpu":model.sample[.gpu] as Any? ?? NSNull(),"ram":model.sample.memoryPercent as Any? ?? NSNull(),
                "processCount":model.processes.count,"recentCount":model.recent.count,"archiveBytes":model.archiveBytes,
                "archiveIssue":model.historyIssue as Any? ?? NSNull(),"expression":model.companion.expression.rawValue,"status":model.companion.status,
                "expanded":model.expanded,"overlayShown":model.overlayShown,"displayMode":model.mode,"opacity":model.overlayPreferences.backgroundOpacity,
                "floatingStyle":model.overlayPreferences.style.rawValue,"floatingLayout":model.floatingLayout.rawValue,
                "autoVertical":model.overlayPreferences.autoVertical,"dockedEdge":model.overlayPreferences.dockedEdge?.rawValue as Any? ?? NSNull(),"isolatedHistoryPath":archive.path,
                "locked":model.overlayPreferences.positionLocked,"reply":model.companionReply as Any? ?? NSNull(),"windows":windows,
                "snoozed":model.snoozedUntil>Date(),"fontRegistered":ForestStyle.fontRegistered,"isolatedDefaultsSuite":suite,
                "frontmostApplication":NSWorkspace.shared.frontmostApplication?.bundleIdentifier as Any? ?? NSNull()]
            if let p=model.overlayPreferences.floatingPosition {status["placement"]=["screen":p.screenID,"horizontal":p.horizontal,"vertical":p.vertical]}
            if let data=try? JSONSerialization.data(withJSONObject:status,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:scratch.appendingPathComponent("ui-check-status.json"),options:.atomic)}
        }
        timer.resume()
        withExtendedLifetime((delegate,timer,cleanup)) { app.run() }
        timer.cancel()
        defaults.removePersistentDomain(forName:suite)
    }
}
