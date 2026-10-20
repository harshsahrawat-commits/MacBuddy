import AppKit
import Combine
import MacBuddyCore
import UserNotifications

final class SamplingService {
    private let queue = DispatchQueue(label: "app.macbuddy.sampling", qos: .utility, autoreleaseFrequency: .workItem)
    private var timer: DispatchSourceTimer?
    private var processTimer: DispatchSourceTimer?
    private let provider: MetricProviding
    private let historyURL: URL?
    private var engine = AdviceEngine()
    private var history: HistoryStore?
    private var recent: [Snapshot] = []
    private var processes: [ProcessReading] = []
    private var sleeping = false
    private var notificationsEnabled = false
    private var snoozedUntil = Date.distantPast
    private var detailOpen = false
    private var interval: TimeInterval = 2
    private var failure: String?
    var onSample: ((Snapshot, [ProcessReading], [Advice], [Snapshot], Int64, String?, [Advice]) -> Void)?

    init(provider: MetricProviding = TelemetryProvider(), historyURL: URL? = nil) {
        self.provider = provider; self.historyURL = historyURL
    }
    private func historyFile() throws -> URL {
        if let historyURL { return historyURL }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("MacBuddy/history.sqlite")
    }
    func start() {
        queue.async { [self] in
            do {
                history = try HistoryStore(url: historyFile())
                try history?.maintain(); try history?.event("App started")
            } catch { failure = error.localizedDescription }
            schedule()
        }
    }
    func configure(details: Bool, samplingMode: String, notifications: Bool, snooze: Date) {
        queue.async { [self] in
            detailOpen = details; notificationsEnabled = notifications; snoozedUntil = snooze
            let desired: TimeInterval = samplingMode == "Eco" ? 5 : details && samplingMode == "Adaptive" ? 1 : 2
            if desired != interval { interval = desired; schedule() }
        }
    }
    private func schedule() {
        timer?.cancel(); timer = nil; processTimer?.cancel(); processTimer = nil
        guard !sleeping else { return }
        let processSource = DispatchSource.makeTimerSource(queue: queue)
        processSource.schedule(deadline: .now(), repeating: 5, leeway: .milliseconds(150))
        processSource.setEventHandler { [weak self] in
            guard let self else { return }
            self.processes = self.provider.processes()
        }
        processTimer = processSource; processSource.resume()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source; source.resume()
    }
    private func tick() {
        let sample = provider.sample(at: Date())
        recent.append(sample); recent.removeAll { sample.timestamp.timeIntervalSince($0.timestamp) > 3600 }
        if recent.count > 3601 { recent.removeFirst(recent.count - 3601) } // Bound memory even after wall-clock corrections.
        let advice = engine.update(sample, notificationsAllowed: notificationsEnabled && sample.timestamp >= snoozedUntil)
        do { try history?.record(sample) } catch { history?.pauseAfterError(error); failure = error.localizedDescription }
        let callback = onSample
        let processSnapshot = processes
        let points = detailOpen ? recent : []
        let bytes = history?.diskUsage ?? 0
        let issue = history?.pausedReason ?? failure
        DispatchQueue.main.async { callback?(sample, processSnapshot, advice.active, points, bytes, issue, advice.notifications) }
    }
    func sleep() {
        queue.async { [self] in
            sleeping = true; timer?.cancel(); timer = nil; processTimer?.cancel(); processTimer = nil
            do { try history?.flush(); try history?.event("Sleep observed") } catch { history?.pauseAfterError(error) }
            history?.resetContinuity(); engine.resetContinuity(); provider.reset()
        }
    }
    func wake() {
        queue.async { [self] in
            sleeping = false; history?.resetContinuity(); engine.resetContinuity(); provider.reset()
            do { try history?.event("Wake observed") } catch { history?.pauseAfterError(error) }
            schedule()
        }
    }
    func loadHistory(from: Date, to: Date, completion: @escaping (Result<HistoryResult, Error>) -> Void) {
        queue.async { [self] in
            let result = Result { () -> HistoryResult in
                guard let history else { throw HistoryError.database(failure ?? "History is starting.") }
                try history.flush()
                return HistoryResult(summaries: try history.query(from: from, to: to), events: try history.events(from: from, to: to), bytes: history.diskUsage, pausedReason: history.pausedReason)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func clearHistory(completion: @escaping (String?) -> Void) {
        queue.async { [self] in
            do {
                guard let history else { throw HistoryError.database(failure ?? "History unavailable.") }
                try history.clear(); recent.removeAll(); failure = nil
                DispatchQueue.main.async { completion(nil) }
            } catch { DispatchQueue.main.async { completion(error.localizedDescription) } }
        }
    }
    func retryHistory() {
        queue.async { [self] in
            do {
                if history == nil {
                    history = try HistoryStore(url: historyFile())
                }
                try history?.retry(); failure = nil
            } catch { failure = error.localizedDescription }
        }
    }
    func stop() {
        queue.sync { [self] in
            timer?.cancel(); timer = nil; processTimer?.cancel(); processTimer = nil
            try? history?.flush(); try? history?.event("App stopped")
            provider.reset()
        }
    }
}

final class MonitorModel: ObservableObject {
    @Published var sample = Snapshot()
    @Published var processes: [ProcessReading] = []
    @Published var advice: [Advice] = []
    @Published var recent: [Snapshot] = []
    @Published var archiveBytes: Int64 = 0
    @Published var historyIssue: String?
    @Published var historyRevision = 0
    @Published var notificationStatus = "Off"
    @Published var deliveryStatus: String?
    @Published var shortcutIssue: String?
    @Published var loginIssue: String?
    @Published var overlayAvailable = false
    @Published var overlayShown = false
    @Published var expanded = false
    @Published var floatingLayout = FloatingLayout.horizontal
    @Published private(set) var companion = CompanionPresentation.checking
    @Published var companionReply: String? { didSet { onCompanionReplyChange?() } }
    var onCompanionReplyChange: (() -> Void)?
    private var companionTracker = CompanionTracker()
    private var companionPhrase = 0
    private var companionReplyIndex = 0
    @Published var overlayPreferences: OverlayPreferences {
        didSet {
            if persistOverlayPreferences { overlayPreferences.save(to: defaults) }
            if oldValue.floatingPosition != overlayPreferences.floatingPosition || oldValue.style != overlayPreferences.style || oldValue.autoVertical != overlayPreferences.autoVertical || oldValue.dockedEdge != overlayPreferences.dockedEdge { onPlacementChange?() }
        }
    }
    @Published var snoozedUntil: Date { didSet { defaults.set(snoozedUntil, forKey: "snoozedUntil"); configure() } }
    @Published var mode: String { didSet { defaults.set(mode, forKey: "displayMode"); onDisplayChange?() } }
    @Published var samplingMode: String { didSet { defaults.set(samplingMode, forKey: "samplingMode"); configure() } }
    @Published var notifications: Bool { didSet { defaults.set(notifications, forKey: "notifications"); updateNotificationPermission(requestIfNeeded: true) } }
    @Published var shortcutKey: String { didSet { saveShortcut() } }
    @Published var control: Bool { didSet { saveShortcut() } }
    @Published var option: Bool { didSet { saveShortcut() } }
    @Published var command: Bool { didSet { saveShortcut() } }
    @Published var shift: Bool { didSet { saveShortcut() } }
    var dashboardOpen = false { didSet { configure() } }
    var onDisplayChange: (() -> Void)?
    var onPlacementChange: (() -> Void)?
    var beginOverlayDrag: (() -> Void)?
    var moveOverlayDrag: ((NSPoint) -> Void)?
    var endOverlayDrag: (() -> Void)?
    var returnToNotch: (() -> Void)?
    var centerOverlay: (() -> Void)?
    var nudgeOverlay: ((CGFloat, CGFloat) -> Void)?
    var onShortcutChange: (() -> Void)?
    var onSampleChange: (() -> Void)?
    var openDashboard: (() -> Void)?
    var openSettings: (() -> Void)?
    var expandOverlay: (() -> Void)?
    let service: SamplingService
    private let defaults: UserDefaults
    private let persistOverlayPreferences: Bool
    private var permission = NotificationPermissionState()
    private var permissionRequestInFlight = false
    var shortcutLabel: String { "\(control ? "⌃" : "")\(option ? "⌥" : "")\(shift ? "⇧" : "")\(command ? "⌘" : "")\(shortcutKey)" }
    init(defaults: UserDefaults = .standard, persistOverlayPreferences: Bool = true, service: SamplingService = SamplingService()) {
        self.service = service
        self.defaults = defaults; self.persistOverlayPreferences = persistOverlayPreferences
        let d = defaults
        overlayPreferences = OverlayPreferences.load(from: d)
        mode = d.string(forKey: "displayMode") ?? "Always visible"
        samplingMode = d.string(forKey: "samplingMode") ?? "Adaptive"
        notifications = d.bool(forKey: "notifications")
        snoozedUntil = d.object(forKey: "snoozedUntil") as? Date ?? .distantPast
        shortcutKey = d.string(forKey: "shortcutKey") ?? "M"
        control = d.object(forKey: "hotkeyControl") as? Bool ?? true
        option = d.object(forKey: "hotkeyOption") as? Bool ?? true
        command = d.object(forKey: "hotkeyCommand") as? Bool ?? true
        shift = d.bool(forKey: "hotkeyShift")
        service.onSample = { [weak self] sample, processes, advice, recent, bytes, issue, notices in
            guard let self else { return }
            self.sample = sample; self.processes = processes; self.advice = advice; self.archiveBytes = bytes; self.historyIssue = issue
            self.updateCompanion(sample, advice: advice)
            if self.expanded || self.dashboardOpen { self.recent = recent } else if !self.recent.isEmpty { self.recent.removeAll() }
            self.onSampleChange?()
            for notice in notices { self.deliver(notice) }
        }
    }
    func updateCompanion(_ sample: Snapshot, advice: [Advice]) {
        let next = companionTracker.update(sample, advice: advice)
        if companion != next { companion = next; companionPhrase = 0; companionReplyIndex = 0 }
        if companionReply != nil { showCompanionReply(advance: false) }
    }
    func showCompanionReply(advance: Bool = true) {
        let lines = companion.lines
        if advance { companionReplyIndex = companionPhrase; companionPhrase = (companionPhrase + 1) % lines.count }
        let message = lines[companionReplyIndex % lines.count]
        if companionReply != message { companionReply = message }
    }
    func setFloatingStyle(_ style: FloatingStyle) {
        let changed = overlayPreferences.style != style
        expanded = false; companionReply = nil; configure()
        overlayPreferences.style = style
        if !changed { onPlacementChange?() }
    }
    func start() { service.start(); updateNotificationPermission() }
    func claimFirstLaunch() -> Bool {
        guard !defaults.bool(forKey: "hasLaunched") else { return false }
        defaults.set(true, forKey: "hasLaunched"); return true
    }
    func refreshNotificationPermission() { if !permissionRequestInFlight { updateNotificationPermission() } }
    func configure() { service.configure(details: expanded || dashboardOpen, samplingMode: samplingMode, notifications: permission.canDeliver, snooze: snoozedUntil) }
    private func saveShortcut() {
        defaults.set(shortcutKey, forKey: "shortcutKey"); defaults.set(control, forKey: "hotkeyControl")
        defaults.set(option, forKey: "hotkeyOption"); defaults.set(command, forKey: "hotkeyCommand"); defaults.set(shift, forKey: "hotkeyShift")
        onShortcutChange?()
    }
    private func updateNotificationPermission(requestIfNeeded: Bool = false) {
        let request = permission.begin(enabled: notifications)
        deliveryStatus = nil
        guard notifications else { notificationStatus = "Off"; configure(); return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self, self.permission.isCurrent(request) else { return }
                if settings.authorizationStatus == .notDetermined && requestIfNeeded {
                    self.permissionRequestInFlight = true
                    center.requestAuthorization(options: [.alert]) { allowed, error in
                        DispatchQueue.main.async {
                            self.permissionRequestInFlight = false
                            guard self.permission.complete(request, authorization: allowed ? .allowed : .denied) else { return }
                            self.notificationStatus = error?.localizedDescription ?? (allowed ? "Allowed · silent" : "Denied in System Settings")
                            self.configure()
                        }
                    }
                } else {
                    let authorization: NotificationPermissionState.Authorization = settings.authorizationStatus == .notDetermined ? .notDetermined : (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional ? .allowed : .denied)
                    guard self.permission.complete(request, authorization: authorization) else { return }
                    self.notificationStatus = authorization == .allowed ? "Allowed · silent" : authorization == .denied ? "Denied in System Settings" : "Permission needed · toggle advisories on to request"
                    self.configure()
                }
            }
        }
    }
    func sendTestNotification() {
        guard permission.canDeliver, Date() >= snoozedUntil else { return }
        let request = permission.generation
        let content = UNMutableNotificationContent()
        content.title = "Mac Buddy · Test notification"
        content.body = "Silent advisories are ready. This is a test, not a detected problem."
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "macbuddy-test", content: content, trigger: nil)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.permission.isCurrent(request) else { return }
                self.deliveryStatus = error?.localizedDescription ?? "Test sent · silent"
            }
        }
    }
    var canSendTestNotification: Bool { permission.canDeliver && Date() >= snoozedUntil }
    private func deliver(_ notice: Advice) {
        guard permission.canDeliver, Date() >= snoozedUntil else { return }
        let request = permission.generation
        let content = UNMutableNotificationContent()
        content.title = "Mac Buddy · \(notice.title)"; content.body = notice.evidence + " " + notice.action
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notice.id, content: content, trigger: nil)) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    guard let self, self.permission.isCurrent(request) else { return }
                    self.deliveryStatus = error.localizedDescription
                }
            }
        }
    }
    func clearHistory(completion: @escaping (String?) -> Void) {
        service.clearHistory { [weak self] error in
            if error == nil { self?.recent.removeAll(); self?.historyRevision += 1 }
            completion(error)
        }
    }
    func openActivityMonitor() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
    func openStorageSettings() { if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) } }
}
