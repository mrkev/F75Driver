//
//  F75DriverApp.swift
//  F75Driver
//
//  Created by Kevin on 11/11/26.
//

import SwiftUI

@main
struct F75DriverApp: App {
    @State private var monitor: KeyboardMonitor

    init() {
        let monitor = KeyboardMonitor()
        _monitor = State(initialValue: monitor)
        // Unit tests are hosted in the app; keep them off the hardware.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            monitor.start()
        }
    }

    var body: some Scene {
        Window("F75 Driver", id: "status") {
            ContentView()
                .environment(monitor)
        }

        MenuBarExtra {
            BatteryMenu()
                .environment(monitor)
        } label: {
            // The menu bar shows the icon and, once known, the battery level.
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                if let battery = monitor.lastBattery {
                    Text("\(battery.level)%")
                }
            }
        }
    }
}
