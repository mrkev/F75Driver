//
//  F75DriverApp.swift
//  F75Driver
//
//  Created by Kevin on 11/11/26.
//

import SwiftUI

@main
struct F75DriverApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("F75 Driver", id: "status") {
            ContentView()
                .environment(appDelegate.monitor)
                .background(WindowOpenerBridge(appDelegate: appDelegate))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = KeyboardMonitor()
    private var statusMenu: StatusMenuController?
    /// SwiftUI's action for reopening the status window, once a view has seen it.
    var openStatusWindow: (() -> Void)?

    /// Unit tests are hosted in the app; keep them off the hardware and the menu bar.
    private var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTesting else { return }
        monitor.start()
        // A status item can only be made once the app is connected to the window server.
        statusMenu = StatusMenuController(monitor: monitor) { [weak self] in
            self?.openStatusWindow?()
        }
    }
}

/// Hands SwiftUI's open-window action to the AppKit menu, which has no
/// other way to reopen a closed SwiftUI window.
private struct WindowOpenerBridge: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            appDelegate.openStatusWindow = { openWindow(id: "status") }
        }
    }
}
