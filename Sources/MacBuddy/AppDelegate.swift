import AppKit
import SwiftUI
import MacBuddyCore
import UserNotifications
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let model: MonitorModel
    init(model: MonitorModel = MonitorModel()) { self.model = model; super.init() }
    private let hotKey = GlobalHotKey()
    private var statusItem: NSStatusItem!
    private var overlay: OverlayController!
    private var dashboard: NSWindow?
    private var settings: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private let stateLogger = Logger(subsystem: "app.macbuddy.personal", category: "state")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem(); let applicationMenu = NSMenu()
        applicationMenuItem.submenu = applicationMenu; mainMenu.addItem(applicationMenuItem)
        add(applicationMenu, "Settings…", #selector(showSettings), key: ",")
        applicationMenu.addItem(.separator())
        add(applicationMenu, "Quit Mac Buddy", #selector(quit), key: "q")
        let windowMenuItem = NSMenuItem(); let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu; mainMenu.addItem(windowMenuItem)
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Mac Buddy")
        statusItem.button?.toolTip = "Mac Buddy"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false; statusItem.menu = menu
        overlay = OverlayController(model: model)
        overlay.preferredScreen = { [weak self] in self?.settings?.screen ?? self?.dashboard?.screen ?? NSScreen.main }
        model.onShortcutChange = { [weak self] in self?.registerShortcut() }
        model.openDashboard = { [weak self] in self?.showDashboard() }
        model.openSettings = { [weak self] in self?.showSettings() }
        model.onSampleChange = { [weak self] in self?.statusItem.button?.toolTip = "Mac Buddy · \(self?.model.sample.thermal.friendly ?? "")" }
        hotKey.action = { [weak self] in self?.toggleOverlay() }
        registerShortcut()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.overlay.update() }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.model.service.sleep() })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.model.service.wake(); self?.overlay.update() })
        // canJoinAllSpaces + stationary handle Spaces membership. Reordering or
        // resizing at each transition can make a stationary overlay blink.
        UNUserNotificationCenter.current().delegate = self
        model.start(); overlay.update()
        if model.claimFirstLaunch() { showDashboard() }
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshNotificationPermission() }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list]) // Explicitly omit sound, including while the dashboard is active.
    }
    private func logState(_ event: String) {
        let state = "\(event) overlay=\(model.overlayShown) expanded=\(model.expanded) dashboard=\(dashboard != nil) settings=\(settings != nil) mode=\(model.mode)"
        stateLogger.notice("\(state, privacy: .public)")
    }
    private func registerShortcut() { model.shortcutIssue = hotKey.register(key: model.shortcutKey, control: model.control, option: model.option, command: model.command, shift: model.shift) }
    @objc private func toggleOverlay() { overlay.toggle() }
    @objc private func resetOverlayPosition() { model.returnToNotch?() }
    @objc private func centerOverlayPosition() { model.centerOverlay?() }
    @objc func showDashboard() {
        model.companionReply = nil
        if dashboard == nil {
            dashboard = window(title: "Mac Buddy", size: NSSize(width: 960, height: 790), view: AnyView(DashboardView(model: model)))
            dashboard?.minSize = NSSize(width: 820, height: 660); dashboard?.delegate = self
        }
        model.dashboardOpen = true; dashboard?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); logState("dashboard-opened")
    }
    @objc func showSettings() {
        model.companionReply = nil
        if settings == nil { settings = window(title: "Mac Buddy Settings", size: NSSize(width: 680, height: 760), view: AnyView(SettingsView(model: model))); settings?.styleMask.remove(.resizable); settings?.delegate = self }
        settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); logState("settings-opened")
    }
    private func window(title: String, size: NSSize, view: AnyView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true; window.backgroundColor = NSColor(red: 15/255, green: 33/255, blue: 26/255, alpha: 1); window.appearance = NSAppearance(named: .darkAqua); window.contentView = NSHostingView(rootView: view); window.center()
        return window
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === dashboard {
            model.dashboardOpen = false
            model.recent.removeAll()
            dashboard?.contentView = nil
            dashboard = nil
        } else if notification.object as? NSWindow === settings {
            settings?.contentView = nil
            settings = nil
        }
        logState("window-closed")
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: "\(model.sample.thermal.friendly) · \(model.sample.thermal.name)", action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status)
        menu.addItem(.separator())
        add(menu, "Open dashboard", #selector(showDashboard))
        let toggle = add(menu, "\(model.overlayShown ? "Hide" : "Show") display (\(model.shortcutLabel))", #selector(toggleOverlay))
        toggle.isEnabled = model.mode != "Off" && model.overlayAvailable
        let modes = NSMenu()
        for mode in ["Always visible", "Shortcut only", "Off"] {
            let item = NSMenuItem(title: mode, action: #selector(changeMode(_:)), keyEquivalent: ""); item.target = self; item.state = model.mode == mode ? .on : .off; modes.addItem(item)
        }
        let modesItem = NSMenuItem(title: "Display mode", action: nil, keyEquivalent: ""); modesItem.submenu = modes; menu.addItem(modesItem)
        let styles = NSMenu()
        for style in FloatingStyle.allCases {
            let item = NSMenuItem(title: style.rawValue, action: #selector(changeFloatingStyle(_:)), keyEquivalent: "")
            item.target = self; item.state = model.overlayPreferences.style == style ? .on : .off; styles.addItem(item)
        }
        let stylesItem = NSMenuItem(title: "Floating display", action: nil, keyEquivalent: ""); stylesItem.submenu = styles; menu.addItem(stylesItem)
        add(menu, "Return to notch", #selector(resetOverlayPosition))
        add(menu, "Center on this screen", #selector(centerOverlayPosition))
        add(menu, "Settings…", #selector(showSettings))
        add(menu, "Snooze advisories for 1 hour", #selector(snooze))
        if !model.overlayAvailable { let item = NSMenuItem(title: "Display unavailable · menu-bar mode", action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        if model.shortcutIssue != nil { let item = NSMenuItem(title: "Shortcut unavailable — see Settings", action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator()); add(menu, "Quit Mac Buddy", #selector(quit), key: "q")
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ selector: Selector, key: String = "") -> NSMenuItem { let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; menu.addItem(item); return item }
    @objc private func changeMode(_ sender: NSMenuItem) { model.mode = sender.title }
    @objc private func changeFloatingStyle(_ sender: NSMenuItem) {
        guard let style = FloatingStyle(rawValue: sender.title) else { return }; model.setFloatingStyle(style)
    }
    @objc private func snooze() { model.snoozedUntil = Date().addingTimeInterval(3600) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { overlay?.stop(); model.service.stop() }
}
