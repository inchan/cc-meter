import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var settings: AppSettingsStore
    @State private var selection: AccountID?
    @State private var lastError: String?
    @State private var draftLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            accountList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))

            displayNameEditor

            actionButtons

            Divider().padding(.vertical, 2)
            displaySection

            if let err = lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footnote
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            Text("계정 목록")
                .font(.headline)
            Spacer()
            Button {
                Task { await monitor.refreshAllOnce() }
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
    }

    private var accountList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if manager.accounts.isEmpty {
                    Text("등록된 계정이 없습니다.\n‘현재 계정 가져오기’ 또는 ‘새 계정 로그인’ 으로 추가하세요.")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(manager.accounts) { acc in
                        AccountSettingsRow(
                            account: acc,
                            isActive: acc.id == manager.activeAccountID,
                            isSelected: selection == acc.id,
                            usage: monitor.snapshots[acc.id],
                            error: monitor.lastError[acc.id],
                            onSelect: { selection = acc.id },
                            onSwitch: { handleSwitch(to: acc.id) }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                handleImportCurrent()
            } label: {
                Label("현재 계정 가져오기", systemImage: "square.and.arrow.down")
            }
            Button {
                handleLogin()
            } label: {
                Label("새 계정 로그인 (Terminal)", systemImage: "person.badge.plus")
            }
            Spacer()
            Button(role: .destructive) {
                handleRemove()
            } label: {
                Label("삭제", systemImage: "trash")
            }
            .disabled(selection == nil || selection == manager.activeAccountID)
        }
    }

    private var displayNameEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("표시 이름")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let id = selection,
                   let acc = manager.accounts.first(where: { $0.id == id }) {
                    Text(acc.emailAddress)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 6) {
                TextField("표시 이름 (예: 회사 / 개인)",
                          text: $draftLabel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selection == nil)
                    .onSubmit { handleRename() }
                Button("변경") { handleRename() }
                    .disabled(selection == nil || draftLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("같은 이메일 prefix(이니셜) 가 겹칠 때 구분에 유용합니다.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .onChange(of: selection) { newValue in
            if let id = newValue, let acc = manager.accounts.first(where: { $0.id == id }) {
                draftLabel = acc.label
            } else {
                draftLabel = ""
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("표시 옵션")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Picker("사용량 표시 방식", selection: Binding(
                get: { settings.settings.usageDisplayMode },
                set: { settings.setDisplayMode($0) }
            )) {
                ForEach(UsageDisplayMode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            Text("‘사용 퍼센트’ 는 누적 사용률, ‘남은 퍼센트’ 는 남은 한도. 색상 임계치는 항상 실제 사용률 기준.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var footnote: some View {
        Text("활성 계정은 삭제할 수 없습니다. Claude Code 가 실행 중이면 계정 전환이 차단됩니다.")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
    }

    // MARK: - actions

    private func handleImportCurrent() {
        do {
            let acc = try manager.importCurrent()
            selection = acc.id
            lastError = nil
        } catch {
            lastError = "가져오기 실패: \(String(describing: error))"
        }
    }

    private func handleLogin() {
        do {
            try manager.openLogin()
            lastError = "Terminal 에서 로그인을 완료한 뒤 ‘현재 계정 가져오기’ 를 누르세요."
        } catch {
            lastError = "Terminal 실행 실패: \(String(describing: error))"
        }
    }

    private func handleRemove() {
        guard let id = selection else { return }
        if id == manager.activeAccountID {
            lastError = "활성 계정은 삭제할 수 없습니다."
            return
        }
        do {
            try manager.remove(id)
            selection = nil
            lastError = nil
        } catch {
            lastError = "삭제 실패: \(String(describing: error))"
        }
    }

    private func handleRename() {
        guard let id = selection else { return }
        let trimmed = draftLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try manager.rename(id, to: trimmed)
            lastError = nil
        } catch {
            lastError = "이름 변경 실패: \(String(describing: error))"
        }
    }

    private func handleSwitch(to id: AccountID) {
        do {
            try manager.switchTo(id)
            lastError = nil
            Task { await monitor.refreshActiveOnce() }
        } catch SwitchError.claudeRunning {
            lastError = "Claude Code 가 실행 중입니다. 모든 세션을 종료한 뒤 다시 시도하세요."
        } catch {
            lastError = "전환 실패: \(String(describing: error))"
        }
    }
}

private struct AccountSettingsRow: View {
    let account: Account
    let isActive: Bool
    let isSelected: Bool
    let usage: UsageSnapshot?
    let error: String?
    let onSelect: () -> Void
    let onSwitch: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: StatusIconRenderer.render(initial: account.initial,
                                                     hex: account.colorHex,
                                                     size: 32))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.label).font(.system(size: 13, weight: .semibold))
                    if isActive {
                        Text("active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .clipShape(.rect(cornerRadius: 3))
                    }
                }
                Text(account.emailAddress)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                usageLine
            }
            Spacer()
            if !isActive {
                Button("전환", action: onSwitch)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var usageLine: some View {
        HStack(spacing: 8) {
            if let u = usage {
                badge("S", percent: u.fiveHourUtilization, level: u.fiveHourLevel)
                if let v = u.sevenDayUtilization {
                    badge("W", percent: v, level: u.sevenDayLevel)
                }
            } else if let err = error {
                Text(err == "unauthorized" ? "재로그인 필요" : "조회 실패")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            } else {
                Text("--").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    private func badge(_ label: String, percent: Int, level: ThresholdLevel) -> some View {
        Text("\(label): \(percent)%")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(level.color)
    }
}
