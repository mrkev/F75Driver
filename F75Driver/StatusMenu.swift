//
//  StatusMenu.swift
//  F75Driver
//
//  The menu bar item and its menu. Built with AppKit because a SwiftUI
//  MenuBarExtra menu cannot hold a custom header row like the system
//  battery menu's.
//

import AppKit
import ServiceManagement
import SwiftUI

extension BatteryStatus.Power {
    var title: String {
        switch self {
        case .onBattery: "On battery"
        case .charging: "Charging"
        case .pluggedInFull: "Plugged in, not charging"
        }
    }
}

final class StatusMenuController: NSObject, NSMenuDelegate {
    private let monitor: KeyboardMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let openStatusWindow: () -> Void

    init(monitor: KeyboardMonitor, openStatusWindow: @escaping () -> Void) {
        self.monitor = monitor
        self.openStatusWindow = openStatusWindow
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "F75 keyboard")
            button.imagePosition = .imageLeading
        }
        observeLabel()
    }

    // MARK: Menu bar label

    private func observeLabel() {
        withObservationTracking {
            updateLabel()
        } onChange: {
            // The controller lives as long as the app, so holding it is fine.
            Task { @MainActor in self.observeLabel() }
        }
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        if let battery = monitor.lastBattery {
            // U+FE0E keeps the bolt monochrome like the rest of the menu bar.
            button.title = battery.power == .charging ? " \(battery.level)% \u{26A1}\u{FE0E}" : " \(battery.level)%"
        } else {
            button.title = ""
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem()
        header.view = headerView()
        menu.addItem(header)

        if let lighting = lightingItem() {
            menu.addItem(.separator())
            menu.addItem(lighting)
        }

        if monitor.present.isEmpty == false && monitor.blocked.isEmpty == false {
            menu.addItem(.separator())
            menu.addItem(ActionItem("Open Input Monitoring Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            })
        }

        menu.addItem(.separator())
        let refresh = ActionItem("Refresh", key: "r") { [monitor] in
            Task { await monitor.refresh() }
        }
        refresh.isEnabled = !monitor.present.isEmpty && !monitor.isRefreshing
        menu.addItem(refresh)
        menu.addItem(ActionItem("Settings…", key: ",") { [weak self] in
            self?.openStatusWindow()
        })
        let login = ActionItem("Open at Login") { [weak self] in self?.toggleLaunchAtLogin() }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit F75 Driver", key: "q") { NSApp.terminate(nil) })
    }

    private func headerView() -> NSView {
        let host = NSHostingView(rootView: StatusMenuHeader(summary: summary()))
        let size = host.fittingSize
        host.frame = NSRect(x: 0, y: 0, width: max(size.width, 250), height: size.height)
        host.autoresizingMask = [.width]
        return host
    }

    /// What the header shows: the model and battery, then how it is connected.
    private func summary() -> StatusMenuHeader.Summary {
        guard let kind = monitor.activeConnection else {
            return .init(title: "AULA F75", value: nil, lines: ["No keyboard connected"])
        }
        if !monitor.blocked.isEmpty {
            return .init(title: "AULA F75", value: nil, lines: ["Input Monitoring permission needed"])
        }
        let status = monitor.status[kind]
        let title = monitor.modelName ?? "AULA F75"

        var lines = ["Connection: \(kind.title)"]
        let level: Int?
        if let battery = status?.battery {
            level = battery.level
            lines.append("Power: \(battery.power.title)")
        } else if status == nil {
            level = monitor.lastBattery?.level
            lines.append("Reading…")
        } else {
            // A sleeping keyboard stops answering the dongle; show what was last read.
            level = monitor.lastBattery?.level
            lines.append("Not answering, probably asleep")
            if let date = monitor.lastBatteryDate {
                lines.append("Last reading \(date.formatted(.relative(presentation: .named)))")
            }
        }
        return .init(title: title, value: level.map { "\($0)%" }, lines: lines)
    }

    /// Lighting effect and brightness, offered only over the cable: the
    /// dongle is read-only.
    private func lightingItem() -> NSMenuItem? {
        guard monitor.present.contains(.cable), !monitor.blocked.contains(.cable),
              let settings = monitor.status[.cable]?.settings else { return nil }
        let busy = monitor.isWritingLighting
        let current = settings.lightingEffect

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for effect in SettingsPage.selectableEffects {
            let item = ActionItem(SettingsPage.effectName(effect)) { [monitor] in
                // Like the main window: use the values stored for that effect.
                let stored = settings.settings(forEffect: effect)
                Task {
                    await monitor.setLighting(effect: effect,
                                              brightness: min(stored?.brightness ?? 0, SettingsPage.maxBrightness),
                                              speed: min(stored?.speed ?? 0, SettingsPage.maxSpeed))
                }
            }
            item.state = effect == current ? .on : .off
            item.isEnabled = !busy
            submenu.addItem(item)
            if effect == 0 { submenu.addItem(.separator()) }
        }

        if current != 0, SettingsPage.selectableEffects.contains(current),
           let stored = settings.settings(forEffect: current) {
            let levels = NSMenu()
            levels.autoenablesItems = false
            for level in 0...SettingsPage.maxBrightness {
                let item = ActionItem("\(level)") { [monitor] in
                    Task {
                        await monitor.setLighting(effect: current, brightness: level,
                                                  speed: min(stored.speed, SettingsPage.maxSpeed))
                    }
                }
                item.state = level == stored.brightness ? .on : .off
                item.isEnabled = !busy
                levels.addItem(item)
            }
            submenu.addItem(.separator())
            let brightness = NSMenuItem(title: "Brightness", action: nil, keyEquivalent: "")
            brightness.submenu = levels
            submenu.addItem(brightness)
        }

        let item = NSMenuItem(title: "Lighting", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

/// The first row of the menu, laid out like the system battery menu: the
/// name in bold with the level on the right, then details in grey.
struct StatusMenuHeader: View {
    struct Summary {
        var title: String
        var value: String?
        var lines: [String]
    }

    let summary: Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(summary.title).fontWeight(.bold)
                Spacer(minLength: 16)
                if let value = summary.value {
                    Text(value).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            ForEach(summary.lines, id: \.self) { line in
                Text(line).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
