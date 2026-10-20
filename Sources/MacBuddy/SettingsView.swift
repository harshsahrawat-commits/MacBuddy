import SwiftUI
import ServiceManagement
import MacBuddyCore

struct SettingsView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var solidBackground: Bool { reduceTransparency || contrast == .increased }
    @ViewState private var loginEnabled = SMAppService.mainApp.status == .enabled
    @ViewState private var clearConfirmation = false
    @ViewState private var clearResult: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CompanionBadge(model: model)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make yourself at home.").font(ForestStyle.font(23, .semibold))
                    Text("Mac Buddy · Settings").foregroundStyle(ForestStyle.secondary)
                }
                Spacer()
            }.padding(24)
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            ForestSection("Display & shortcut") {
                Picker("Display mode", selection: $model.mode) {
                    Text("Always visible").tag("Always visible"); Text("Shortcut only").tag("Shortcut only"); Text("Off").tag("Off")
                }
                Text("The shortcut toggles the strip without taking typing focus. Monitoring and history continue when the strip is hidden.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                if !model.overlayAvailable { Label("No notched display is available. Use Center on this screen for floating placement, or access Mac Buddy from the menu bar.", systemImage: "display.trianglebadge.exclamationmark").font(ForestStyle.font(11)) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Global shortcut")
                    HStack {
                        Toggle("⌃", isOn: $model.control).help("Control").accessibilityLabel("Control modifier")
                        Toggle("⌥", isOn: $model.option).help("Option").accessibilityLabel("Option modifier")
                        Toggle("⌘", isOn: $model.command).help("Command").accessibilityLabel("Command modifier")
                        Toggle("⇧", isOn: $model.shift).help("Shift").accessibilityLabel("Shift modifier")
                        Picker("Letter", selection: $model.shortcutKey) { ForEach(GlobalHotKey.keyCodes.keys.sorted(), id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 60)
                    }.toggleStyle(ForestChipToggleStyle())
                }
                Text("Uses physical letter-key positions. No general keyboard monitoring or Accessibility permission is required.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                if let issue = model.shortcutIssue { Text(issue).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.warning) }
            }
            ForestSection("Appearance") {
                Picker("Floating display", selection: Binding(get: { model.overlayPreferences.style }, set: { model.setFloatingStyle($0) })) {
                    ForEach(FloatingStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text("Pebble only keeps just the avatar on screen. Click it for details; drag the avatar to move it. The menu bar always remains available.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                Toggle("Turn vertical at side edges", isOn: $model.overlayPreferences.autoVertical)
                Text("Drop the metric strip near the left or right edge to dock it vertically. Drag away to return to a horizontal strip.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                LabeledContent("Background opacity", value: solidBackground ? "100% · macOS setting" : "\(Int((model.overlayPreferences.backgroundOpacity * 100).rounded()))%")
                Slider(value: $model.overlayPreferences.backgroundOpacity, in: 0.60...1, step: 0.05) {
                    Text("Background opacity")
                }.labelsHidden().accessibilityLabel("Background opacity").disabled(solidBackground)
                    .accessibilityValue("\(Int(((solidBackground ? 1 : model.overlayPreferences.backgroundOpacity) * 100).rounded())) percent")
                Text(reduceTransparency ? "macOS Reduce Transparency is enabled, so the background stays solid." : contrast == .increased ? "macOS Increase Contrast is enabled, so the background stays solid." : "Lower values reveal more of your screen. Text stays opaque for readability.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
            }
            ForestSection("Placement") {
                LabeledContent("Position", value: model.overlayPreferences.floatingPosition == nil ? "Near notch" : "Custom · saved")
                Text("Drag the dotted handle on the strip, or drag Pebble in avatar-only mode. Your position is remembered.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                HStack {
                    Button("Return to notch") { model.returnToNotch?() }
                    Button("Center on this screen") { model.centerOverlay?() }
                }
                Toggle("Lock dragging", isOn: $model.overlayPreferences.positionLocked)
                HStack {
                    Text("Adjust position")
                    Spacer()
                    nudge("arrow.left", "Move left", -20, 0)
                    nudge("arrow.up", "Move up", 0, 20)
                    nudge("arrow.down", "Move down", 0, -20)
                    nudge("arrow.right", "Move right", 20, 0)
                }
            }
            ForestSection("Monitoring") {
                Picker("Sampling", selection: $model.samplingMode) { Text("Adaptive · 2s / 1s in details").tag("Adaptive"); Text("Steady · 2 seconds").tag("Steady"); Text("Eco · 5 seconds").tag("Eco") }
                Text("Processes refresh every 5 seconds; storage every minute. Sampling pauses during sleep. Eco mode reduces refresh frequency.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        model.loginIssue = SMAppService.mainApp.status == .requiresApproval ? "Approve Mac Buddy in System Settings > General > Login Items." : nil
                    } catch { model.loginIssue = error.localizedDescription }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                }))
                if let issue = model.loginIssue { Text(issue).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.warning) }
            }
            ForestSection("Notifications") {
                Toggle("Enable silent advisories", isOn: $model.notifications)
                LabeledContent("Permission", value: model.notificationStatus)
                if let status = model.deliveryStatus { Text(status).font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary) }
                Button("Send test notification") { model.sendTestNotification() }.disabled(!model.canSendTestNotification)
                HStack {
                    Button("Snooze for 1 hour") { model.snoozedUntil = Date().addingTimeInterval(3600) }
                    if model.snoozedUntil > Date() { Button("Resume") { model.snoozedUntil = .distantPast }; Text("Until \(model.snoozedUntil.formatted(date: .omitted, time: .shortened))").font(ForestStyle.font(11)) }
                }
                Text("15-minute cooldown per category; worsening severity can notify sooner. A condition must recover for 2 minutes before resolving. Notification heuristics are Mac Buddy's, not Apple-certified limits.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
            }
            ForestSection("Local archive") {
                LabeledContent("Usage", value: String(format: "%.2f MiB / 100 MiB", Double(model.archiveBytes) / 1_048_576))
                Text("One hour of samples in memory, 30 days of minute summaries, then daily archives. Process names and identifiers are never persisted.").font(ForestStyle.font(11)).foregroundStyle(ForestStyle.secondary)
                if let issue = model.historyIssue { Text(issue).foregroundStyle(ForestStyle.warning).font(ForestStyle.font(11)); Button("Retry recording") { model.service.retryHistory() } }
                Button("Clear history…", role: .destructive) { clearConfirmation = true }
                if let clearResult { Text(clearResult).font(ForestStyle.font(11)) }
            }
            }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }.frame(width: 680, height: 760).modifier(ForestWindowStyle())
            .onAppear { loginEnabled = SMAppService.mainApp.status == .enabled; model.refreshNotificationPermission() }
            .confirmationDialog("Clear all Mac Buddy history?", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { model.clearHistory { clearResult = $0 ?? "History cleared." } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This deletes stored summaries and lifecycle observations. Saved PDF reports are unaffected.") }
    }
    private func nudge(_ symbol: String, _ label: String, _ x: CGFloat, _ y: CGFloat) -> some View {
        Button { model.nudgeOverlay?(x, y) } label: { Image(systemName: symbol) }.accessibilityLabel(label).help(label)
    }
}
