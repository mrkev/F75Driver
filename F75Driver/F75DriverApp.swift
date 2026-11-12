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

enum StatusWindow {
    /// Content width of the status window, the same for every tab.
    static let width: CGFloat = 460
    static let minHeight: CGFloat = 520
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

    /// A settings-style window with General and Advanced tabs in its toolbar.
    private func makeStatusWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab(GeneralView(), label: "General", symbol: "gearshape"))
        tabs.addTabViewItem(tab(AdvancedView(), label: "Advanced", symbol: "gearshape.2"))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        // Fixed width, resizable height. Set on the window: the tab view
        // controller does not pass its children's size limits on.
        window.contentMinSize = NSSize(width: StatusWindow.width, height: StatusWindow.minHeight)
        window.contentMaxSize = NSSize(width: StatusWindow.width, height: .greatestFiniteMagnitude)
        window.setContentSize(NSSize(width: StatusWindow.width, height: 720))
        window.center()
        // Restores the saved frame if there is one; keep only its height and position.
        window.setFrameAutosaveName("StatusWindow")
        let content = window.contentRect(forFrameRect: window.frame)
        if content.width != StatusWindow.width {
            window.setContentSize(NSSize(width: StatusWindow.width, height: max(content.height, StatusWindow.minHeight)))
        }
        return window
    }

    private func tab<Content: View>(_ content: Content, label: String, symbol: String) -> NSTabViewItem {
        let host = NSHostingController(rootView: content.environment(monitor))
        // No preferred size, so switching tabs keeps the window's size.
        host.sizingOptions = []
        // The window title follows the selected tab.
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
