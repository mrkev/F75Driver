//
//  AdvancedView.swift
//  F75Driver
//
//  The Advanced tab: what each connection reported, down to the raw bytes.
//

import SwiftUI

struct AdvancedView: View {
    @Environment(KeyboardMonitor.self) private var monitor

    var body: some View {
        Form {
            if monitor.present.isEmpty {
                Section {
                    Text("No keyboard connected.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(ConnectionKind.allCases) { kind in
                if monitor.present.contains(kind) {
                    ConnectionDetails(kind: kind)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: StatusWindow.width)
        .frame(minHeight: StatusWindow.minHeight)
    }
}

private struct ConnectionDetails: View {
    @Environment(KeyboardMonitor.self) private var monitor
    let kind: ConnectionKind

    var body: some View {
        Section {
            if monitor.blocked.contains(kind) {
                LabeledContent("Status", value: "Waiting for Input Monitoring permission")
            } else if let status = monitor.status[kind] {
                if let error = status.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                if let identity = status.identity {
                    LabeledContent("Model", value: identity.modelName ?? "Unknown")
                    LabeledContent("Model ID") {
                        Text(identity.hex).monospaced().textSelection(.enabled)
                    }
                }
                if let battery = status.battery {
                    LabeledContent("Battery", value: "\(battery.level)%")
                    LabeledContent("Power", value: battery.power.title)
                    LabeledContent("Battery status byte") {
                        Text(String(format: "%02X", battery.statusCode)).monospaced()
                    }
                }
                if let updated = status.updated {
                    LabeledContent("Updated") { Text(updated, style: .time) }
                }
            } else {
                LabeledContent("Status", value: "Reading…")
            }
        } header: {
            SectionTitle(kind.title)
        }
        if let raw = monitor.status[kind]?.raw, !raw.isEmpty {
            Section {
                ForEach(raw, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.name) · \(item.bytes.count) bytes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(hexDump(item.bytes))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                SectionTitle("Raw data · \(kind.title)")
            }
        }
    }

    private func hexDump(_ bytes: [UInt8]) -> String {
        stride(from: 0, to: bytes.count, by: 16).map { start in
            bytes[start..<min(start + 16, bytes.count)].map { String(format: "%02X", $0) }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

#Preview {
    AdvancedView()
        .environment(KeyboardMonitor())
}
