//
//  BatteryMenu.swift
//  F75Driver
//
//  The menu behind the menu bar battery item.
//

import AppKit
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

struct BatteryMenu: View {
    @Environment(KeyboardMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if monitor.present.isEmpty {
            Text("No keyboard found")
        } else if !monitor.blocked.isEmpty {
            Text("Input Monitoring permission needed")
        } else {
            ForEach(ConnectionKind.allCases) { kind in
                if monitor.present.contains(kind) {
                    Text(line(for: kind))
                }
            }
        }

        Divider()

        Button("Refresh") {
            Task { await monitor.refresh() }
        }
        .disabled(monitor.present.isEmpty || monitor.isRefreshing)

        Button("Open F75 Driver") {
            openWindow(id: "status")
            NSApp.activate()
        }

        Divider()

        Button("Quit F75 Driver") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func line(for kind: ConnectionKind) -> String {
        guard let status = monitor.status[kind] else { return "\(kind.title): reading…" }
        if let battery = status.battery {
            return "\(kind.title): \(battery.level)%, \(battery.power.title.lowercased())"
        }
        // A sleeping keyboard stops answering the dongle; show what was last read.
        if let battery = monitor.lastBattery { return "\(kind.title): not answering (last \(battery.level)%)" }
        return "\(kind.title): not answering"
    }
}
