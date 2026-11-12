//
//  ContentView.swift
//  F75Driver
//

import SwiftUI

struct ContentView: View {
    @Environment(KeyboardMonitor.self) private var monitor

    var body: some View {
        Form {
            if monitor.present.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No keyboard found",
                        systemImage: "keyboard",
                        description: Text("Connect the AULA F75 with its USB cable (switch set to USB) or plug in its 2.4 GHz dongle.")
                    )
                }
            }
            if !monitor.blocked.isEmpty {
                PermissionSection()
            }
            ForEach(ConnectionKind.allCases) { kind in
                if monitor.present.contains(kind) {
                    ConnectionSection(kind: kind)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
        .toolbar {
            ToolbarItem {
                if monitor.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await monitor.refresh() }
                    }
                    .disabled(monitor.present.isEmpty)
                }
            }
        }
    }
}

private struct PermissionSection: View {
    @Environment(KeyboardMonitor.self) private var monitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Permission needed") {
            Label {
                Text("macOS requires Input Monitoring permission before an app can talk to a keyboard. F75 Driver only reads the keyboard's settings; it does not record what you type. After turning it on in System Settings, quit and reopen F75 Driver.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            HStack {
                if monitor.access == .undetermined {
                    Button("Allow Access…") { monitor.requestAccess() }
                } else {
                    Button("Open Input Monitoring Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                            openURL(url)
                        }
                    }
                }
                Button("Try Again") { monitor.retry() }
            }
            if monitor.access == .granted {
                Text("Permission is granted but the keyboard is still blocked. Quit and reopen F75 Driver.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConnectionSection: View {
    @Environment(KeyboardMonitor.self) private var monitor
    let kind: ConnectionKind

    var body: some View {
        let status = monitor.status[kind]
        Section(kind.title) {
            if monitor.blocked.contains(kind) {
                LabeledContent("Status", value: "Waiting for permission")
            } else if let status {
                if let error = status.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                if let identity = status.identity {
                    LabeledContent("Model", value: identity.modelName ?? "Unknown")
                    LabeledContent("Model ID", value: identity.hex)
                }
                if let battery = status.battery {
                    LabeledContent("Battery") {
                        HStack(spacing: 8) {
                            ProgressView(value: Double(min(max(battery.level, 0), 100)), total: 100)
                                .frame(width: 90)
                            Text("\(battery.level)%").monospacedDigit()
                        }
                    }
                    LabeledContent("Power", value: battery.power.title)
                }
                if let settings = status.settings {
                    SettingsRows(settings: settings)
                    if kind == .cable {
                        LightingControls(settings: settings)
                    }
                }
                if !status.raw.isEmpty {
                    DisclosureGroup("Raw data") {
                        ForEach(status.raw, id: \.name) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.caption).foregroundStyle(.secondary)
                                Text(hexDump(item.bytes))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if let updated = status.updated {
                    LabeledContent("Updated") { Text(updated, style: .time) }
                }
            } else {
                LabeledContent("Status", value: "Reading…")
            }
        }
    }

    private func hexDump(_ bytes: [UInt8]) -> String {
        stride(from: 0, to: bytes.count, by: 16).map { start in
            bytes[start..<min(start + 16, bytes.count)].map { String(format: "%02X", $0) }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

/// Changes the stored lighting. Offered over the cable only.
private struct LightingControls: View {
    @Environment(KeyboardMonitor.self) private var monitor
    let settings: SettingsPage

    @State private var effect = 0
    @State private var brightness = 0
    @State private var speed = 0

    var body: some View {
        Picker("Change effect", selection: $effect) {
            ForEach(SettingsPage.selectableEffects, id: \.self) { id in
                Text(SettingsPage.effectName(id)).tag(id)
            }
        }
        if effect != 0 {
            Stepper("Brightness: \(brightness)", value: $brightness, in: 0...SettingsPage.maxBrightness)
            Stepper("Speed: \(speed)", value: $speed, in: 0...SettingsPage.maxSpeed)
        }
        LabeledContent {
            Button("Apply to Keyboard") {
                Task { await monitor.setLighting(effect: effect, brightness: brightness, speed: speed) }
            }
            .disabled(monitor.isWritingLighting || !hasChanges)
        } label: {
            if let error = monitor.lightingError {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Saved on the keyboard when applied.").foregroundStyle(.secondary)
            }
        }
        // Follow what the keyboard reports, and load an effect's stored values when it is picked.
        .task(id: settings.bytes) {
            effect = SettingsPage.selectableEffects.contains(settings.lightingEffect) ? settings.lightingEffect : 0
            loadStoredValues()
        }
        .onChange(of: effect) { loadStoredValues() }
    }

    private func loadStoredValues() {
        guard let stored = settings.settings(forEffect: effect) else { return }
        brightness = min(stored.brightness, SettingsPage.maxBrightness)
        speed = min(stored.speed, SettingsPage.maxSpeed)
    }

    private var hasChanges: Bool {
        settings.settingLighting(effect: effect, brightness: brightness, speed: speed).map { $0 != settings } ?? false
    }
}

private struct SettingsRows: View {
    let settings: SettingsPage

    var body: some View {
        LabeledContent("Lighting effect", value: settings.lightingEffectName)
        if let effect = settings.settings(forEffect: settings.lightingEffect) {
            LabeledContent("Brightness", value: "\(effect.brightness)")
            LabeledContent("Speed", value: "\(effect.speed)")
        }
        LabeledContent("Polling rate", value: settings.pollingRateHz.map { "\($0) Hz" } ?? "Level \(settings.pollingLevel)")
        LabeledContent("Sleep after", value: sleepText)
        LabeledContent("Mac layout", value: settings.macMode ? "On" : "Off")
        LabeledContent("Win lock", value: settings.winLock ? "On" : "Off")
        LabeledContent("Low latency", value: settings.lowLatency ? "On" : "Off")
    }

    private var sleepText: String {
        guard let seconds = settings.sleepSeconds else { return "Never" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

#Preview {
    ContentView()
        .environment(KeyboardMonitor())
}
