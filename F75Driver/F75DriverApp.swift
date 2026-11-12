//
//  F75DriverApp.swift
//  F75Driver
//
//  Created by Kevin on 11/11/26.
//
//  A menu bar app with no Dock icon (LSUIElement). The status window is an
//  AppKit window owned by the app delegate, so the menu bar item and a
//  reopen from Finder can show it whether or not it was ever open.
//

import SwiftUI

@main
struct F75DriverApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // SwiftUI needs a scene; the window itself is made by AppDelegate.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showStatusWindow() }
                    .keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = KeyboardMonitor()
    private var statusMenu: StatusMenuController?
    private var statusWindow: NSWindow?

    /// Unit tests are hosted in the app; keep them off the hardware and the menu bar.
    private var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTesting else { return }
        monitor.start()
        // A status item can only be made once the app is connected to the window server.
        statusMenu = StatusMenuController(monitor: monitor) { [weak self] in
            self?.showStatusWindow()
        }
        // Start quietly in the menu bar, except on the first launch and
        // while Input Monitoring still needs to be granted.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") || monitor.access != .granted {
            defaults.set(true, forKey: "hasLaunchedBefore")
            showStatusWindow()
        }
    }

    /// Opening the app again, from Finder or Spotlight, shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusWindow()
        return false
    }

    /// Closing the window leaves the app running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showStatusWindow() {
        let window = statusWindow ?? makeStatusWindow()
        statusWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeStatusWindow() -> NSWindow {
        let host = NSHostingController(rootView: ContentView().environment(monitor))
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        window.title = "F75 Driver"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 720))
        window.center()
        window.setFrameAutosaveName("StatusWindow")
        return window
    }
}
