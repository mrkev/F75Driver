//
//  LaunchAtLogin.swift
//  F75Driver
//
//  Open at Login, shared by the menu and the General tab.
//

import AppKit
import ServiceManagement
import SwiftUI

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Registers or unregisters the app. macOS may ask the user to approve
    /// it in System Settings first, which this opens.
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

/// A toggle that follows the system setting, including changes made in
/// System Settings while the app is running.
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval

    var body: some View {
        Toggle("Open at Login", isOn: Binding(
            get: { isEnabled },
            set: { newValue in
                LaunchAtLogin.setEnabled(newValue)
                update()
            }
        ))
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                update()
            }
        }
        if needsApproval {
            LabeledContent {
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            } label: {
                Text("Waiting for approval in System Settings.").foregroundStyle(.secondary)
            }
        }
    }

    private func update() {
        isEnabled = LaunchAtLogin.isEnabled
        needsApproval = LaunchAtLogin.needsApproval
    }
}
