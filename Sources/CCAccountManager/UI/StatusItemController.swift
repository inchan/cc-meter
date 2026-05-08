import AppKit
import SwiftUI
import Combine

/// AppKit NSStatusItem 직접 제어. SwiftUI MenuBarExtra 의 NSImage 라이프사이클 이슈 회피.
/// AccountManager / UsageMonitor / AppSettingsStore 변경 시 button.image 를 재생성.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let manager: AccountManager
    private let monitor: UsageMonitor
    private let settings: AppSettingsStore
    private var cancellables: Set<AnyCancellable> = []

    init(manager: AccountManager, monitor: UsageMonitor, settings: AppSettingsStore) {
        self.manager = manager
        self.monitor = monitor
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true
        // 모든 NSHostingController 는 .sized factory 사용. sizingOptions 누락 차단.
        self.popover.contentViewController = HostingFactory.make(
            AccountMenuView(manager: manager, monitor: monitor, settings: settings)
        )

        configureButton()
        bindUpdates()
        refreshImage()
        scheduleSelfCheck()
    }

    /// 1초 후 button.image 가 정상 size 인지 자가 검증. 실패 시 ERROR 로깅.
    /// 추후 회귀(라이프사이클/render path)를 즉시 알 수 있도록.
    private func scheduleSelfCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let size = self.statusItem.button?.image?.size ?? .zero
            if size.width < 10 || size.height < 10 {
                Log.app.error("[SELF-CHECK FAIL] status bar image size=\(size.debugDescription, privacy: .public) — 라벨이 보이지 않을 가능성")
            } else {
                Log.app.info("[SELF-CHECK OK] status bar image size=\(size.debugDescription, privacy: .public)")
            }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func bindUpdates() {
        // 데이터 변경 시 메뉴바 라벨 재생성
        manager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshImage() }
            .store(in: &cancellables)
        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshImage() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshImage() }
            .store(in: &cancellables)
    }

    private func refreshImage() {
        guard let button = statusItem.button else { return }
        let acc = activeAccount
        let snap = activeUsage
        let mode = settings.settings.usageDisplayMode
        let fiveDisplay: Int? = snap.map { mode.display(utilization: $0.fiveHourUtilization) }
        let sevenDisplay: Int? = snap.flatMap { s in
            s.sevenDayUtilization.map { mode.display(utilization: $0) }
        }
        button.image = StatusIconRenderer.renderStatusBar(
            initial: acc?.initial ?? "?",
            hex: acc?.colorHex ?? "#888888",
            fiveHour: fiveDisplay,
            fiveLevel: snap?.fiveHourLevel,
            sevenDay: sevenDisplay,
            sevenLevel: snap?.sevenDayLevel
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else {
            Log.ui.error("[POPOVER] statusItem.button is nil")
            return
        }
        // DEBUG: anchor 진단 로그
        let bBounds = button.bounds
        let bFrame = button.frame
        let winFrame = button.window?.frame ?? .zero
        let screenFrame = button.window?.screen?.frame ?? .zero
        let hostSize = popover.contentViewController?.preferredContentSize ?? .zero
        Log.ui.info("[POPOVER pre-show] button.bounds=\(bBounds.debugDescription, privacy: .public) button.frame=\(bFrame.debugDescription, privacy: .public) window.frame=\(winFrame.debugDescription, privacy: .public) screen=\(screenFrame.debugDescription, privacy: .public) hostPref=\(hostSize.debugDescription, privacy: .public)")

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // post-show: 실제 popover window 위치
        if let pw = popover.contentViewController?.view.window {
            Log.ui.info("[POPOVER post-show] popoverWindow.frame=\(pw.frame.debugDescription, privacy: .public) isVisible=\(pw.isVisible)")
        } else {
            Log.ui.error("[POPOVER post-show] popover window nil")
        }
        popover.contentViewController?.view.window?.makeKey()
        manager.reload()
        Task { await monitor.refreshActiveOnce() }
    }

    private var activeAccount: Account? {
        guard let id = manager.activeAccountID else { return nil }
        return manager.accounts.first { $0.id == id }
    }

    private var activeUsage: UsageSnapshot? {
        guard let id = manager.activeAccountID else { return nil }
        return monitor.snapshots[id]
    }
}
