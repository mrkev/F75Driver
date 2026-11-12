//
//  GeneralView.swift
//  F75Driver
//
//  The General tab: the keyboard, its lighting and settings, and the app's
//  own options.
//

import SwiftUI

struct GeneralView: View {
    @Environment(KeyboardMonitor.self) private var monitor

    var body: some View {
        Form {
            Section {
            } header: {
                KeyboardHeader()
            }
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
            Section {
                LaunchAtLoginToggle()
            } header: {
                SectionTitle("App")
            }
            if let kind = monitor.activeConnection, !monitor.blocked.contains(kind),
               let status = monitor.status[kind] {
                if let error = status.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                if let settings = status.settings {
                    Section {
                        if kind == .cable {
                            LightingControls(settings: settings)
                        } else {
                            LightingRows(settings: settings)
                            Text("Lighting can be changed over the USB cable.")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        SectionTitle("Lighting")
                    }
                    Section {
                        KeyboardSettingsRows(settings: settings)
                    } header: {
                        SectionTitle("Keyboard")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: StatusWindow.width)
        .frame(minHeight: StatusWindow.minHeight)
    }
}

/// A section title with one fixed style. A grouped form gives the first
/// section header a smaller, lighter style than the rest, which made the
/// title under the keyboard drawing look different from the others.
struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

/// The drawing of the keyboard with its name and battery underneath.
private struct KeyboardHeader: View {
    @Environment(KeyboardMonitor.self) private var monitor

    var body: some View {
        VStack(spacing: 10) {
            KeyboardIllustration()
                .frame(maxWidth: 520)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .opacity(monitor.activeConnection == nil ? 0.45 : 1)
            VStack(spacing: 2) {
                Text(monitor.modelName ?? "AULA F75")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .monospacedDigit()
                    // The window is hosted by AppKit, so this sits here
                    // rather than in a toolbar.
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await monitor.refresh() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(monitor.present.isEmpty || monitor.isRefreshing)
                    .help("Read the keyboard again")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        guard let kind = monitor.activeConnection else { return "Not connected" }
        var parts = [kind.title]
        if let battery = monitor.status[kind]?.battery ?? monitor.lastBattery {
            parts.append("\(battery.level)%")
            parts.append(battery.power.title)
        }
        return parts.joined(separator: " · ")
    }
}

private struct PermissionSection: View {
    @Environment(KeyboardMonitor.self) private var monitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
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
        } header: {
            SectionTitle("Permission needed")
        }
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
        Picker("Effect", selection: $effect) {
            ForEach(SettingsPage.selectableEffects, id: \.self) { id in
                Text(SettingsPage.effectName(id)).tag(id)
            }
            // An effect the app does not offer, such as custom lighting, is shown but cannot be picked.
            if !SettingsPage.selectableEffects.contains(settings.lightingEffect) {
                Text(settings.lightingEffectName).tag(settings.lightingEffect).selectionDisabled()
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
            effect = settings.lightingEffect
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

/// The stored lighting, read-only.
private struct LightingRows: View {
    let settings: SettingsPage

    var body: some View {
        LabeledContent("Effect", value: settings.lightingEffectName)
        if let effect = settings.settings(forEffect: settings.lightingEffect) {
            LabeledContent("Brightness", value: "\(effect.brightness)")
            LabeledContent("Speed", value: "\(effect.speed)")
        }
    }
}

private struct KeyboardSettingsRows: View {
    let settings: SettingsPage

    var body: some View {
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
    GeneralView()
        .environment(KeyboardMonitor())
}
