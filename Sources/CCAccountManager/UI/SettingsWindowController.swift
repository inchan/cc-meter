import AppKit
import SwiftUI

/// 메뉴바 popover 와 분리된 설정 NSWindow.
/// LSUIElement 앱이라 일반 윈도우 표시 시 NSApp.activate 필요.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    func show(manager: AccountManager, monitor: UsageMonitor, settings: AppSettingsStore) {
        if let win = window {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let host = HostingFactory.make(
            SettingsView(manager: manager, monitor: monitor, settings: settings)
        )
        let win = NSWindow(contentViewController: host)
        win.title = "CC Account Manager 설정"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 520, height: 460))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
