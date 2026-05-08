import SwiftUI
import AppKit

/// 메뉴바 popover 메인 뷰.
struct AccountMenuView: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var settings: AppSettingsStore
    @State private var lastOpenedAt: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activeHeader
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            UsageBar(title: "세션 사용량",
                     utilization: activeUsage?.fiveHourUtilization,
                     resetsAt: activeUsage?.fiveHourResetsAt,
                     level: activeUsage?.fiveHourLevel,
                     mode: settings.settings.usageDisplayMode)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            UsageBar(title: "주간 사용량",
                     utilization: activeUsage?.sevenDayUtilization,
                     resetsAt: activeUsage?.sevenDayResetsAt,
                     level: activeUsage?.sevenDayLevel,
                     mode: settings.settings.usageDisplayMode)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            actionRow
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .onAppear {
            let now = Date()
            if now.timeIntervalSince(lastOpenedAt) > 5 {
                manager.reload()
                Task { await monitor.refreshActiveOnce() }
                lastOpenedAt = now
            }
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                SettingsWindowController.shared.show(manager: manager,
                                                     monitor: monitor,
                                                     settings: settings)
            } label: {
                Label("설정", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")

            Divider().padding(.vertical, 2)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("종료", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
    }

    private var activeUsage: UsageSnapshot? {
        guard let id = manager.activeAccountID else { return nil }
        return monitor.snapshots[id]
    }

    private var activeAccount: Account? {
        guard let id = manager.activeAccountID else { return nil }
        return manager.accounts.first { $0.id == id }
    }

    private var activeHeader: some View {
        HStack(spacing: 10) {
            if let acc = activeAccount {
                Image(nsImage: StatusIconRenderer.render(initial: acc.initial,
                                                         hex: acc.colorHex,
                                                         size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(acc.label)
                            .font(.system(size: 13, weight: .semibold))
                        Text("(활성화)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text(acc.emailAddress)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Image(systemName: "person.crop.circle.dashed")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                Text("등록된 활성 계정 없음")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

private struct UsageBar: View {
    let title: String
    let utilization: Int?
    let resetsAt: Date?
    let level: ThresholdLevel?
    let mode: UsageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(level?.color ?? .secondary)
            }
            ProgressBar(percent: barPercent, color: (level ?? .healthy).color)
                .frame(height: 5)  // 8pt -> 5pt (≈60%)
            if let reset = resetsAt, reset > Date() {
                Text("리셋 \(formatRemaining(reset))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var percentText: String {
        guard let u = utilization else { return "--%" }
        return "\(mode.display(utilization: u))%"
    }

    /// 진행률 바는 항상 utilization (실제 사용량) 그대로 그린다.
    /// 표시 숫자만 mode 에 따라 변환.
    private var barPercent: Int {
        utilization ?? 0
    }

    private func formatRemaining(_ date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSinceNow))
        let h = s / 3600
        let m = (s % 3600) / 60
        let d = h / 24
        if d > 0 { return "\(d)일 \(h % 24)시간 후" }
        if h > 0 { return "\(h)시간 \(m)분 후" }
        return "\(m)분 후"
    }
}

private struct ProgressBar: View {
    let percent: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
    }
}
