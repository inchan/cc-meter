import Foundation
import Combine

/// 활성/비활성 계정의 사용량을 주기적으로 폴링하고 캐시한다.
@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var snapshots: [AccountID: UsageSnapshot] = [:]
    @Published private(set) var lastError: [AccountID: String] = [:]
    /// 429 발생 시 다음 폴링 가능한 시각.
    private var nextEligibleAt: [AccountID: Date] = [:]

    private weak var accountManager: AccountManager?
    private let client: UsageClientProtocol
    private let snapshotStore: ProfileSnapshotStoreProtocol
    private let settingsStore: SettingsStoreProtocol
    private let clock: ClockProtocol

    private var activeTimer: Timer?
    private var inactiveTimer: Timer?

    init(accountManager: AccountManager,
         client: UsageClientProtocol = UsageClient(),
         snapshotStore: ProfileSnapshotStoreProtocol = ProfileSnapshotStore(),
         settingsStore: SettingsStoreProtocol = SettingsStore(),
         clock: ClockProtocol = SystemClock()) {
        self.accountManager = accountManager
        self.client = client
        self.snapshotStore = snapshotStore
        self.settingsStore = settingsStore
        self.clock = clock
        // init 시점에 accounts 가 비었어도 OK — 아래 observer 가 reload 시 자동 채움.
        loadCachedSnapshots()
        observeAccountChanges()
        observeAccountListChanges()
    }

    /// AccountManager.accounts 가 갱신될 때마다 cached snapshots 를 재로드.
    /// init 순서(monitor before reload)에 의존하지 않도록 — 원천 차단.
    private func observeAccountListChanges() {
        accountManager?.$accounts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadCachedSnapshots()
            }
            .store(in: &accountObservers)
    }

    private var accountObservers: Set<AnyCancellable> = []

    /// 새 토큰 import / 스위치 직후 호출되어 backoff 를 풀고 즉시 재폴링한다.
    func invalidateBackoff(for accountID: AccountID) {
        nextEligibleAt[accountID] = nil
        lastError[accountID] = nil
        Task { await refresh(accountID: accountID) }
    }

    private func observeAccountChanges() {
        NotificationCenter.default.addObserver(
            forName: .ccAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let id = note.userInfo?["accountID"] as? AccountID
            Task { @MainActor in
                if let id { self.invalidateBackoff(for: id) }
            }
        }
    }

    func start() {
        let s = settingsStore.load()
        scheduleActive(every: TimeInterval(s.pollIntervalActiveSeconds))
        scheduleInactive(every: TimeInterval(s.pollIntervalInactiveSeconds))
        Task { await refreshActiveOnce() }
    }

    func stop() {
        activeTimer?.invalidate(); activeTimer = nil
        inactiveTimer?.invalidate(); inactiveTimer = nil
    }

    func refreshActiveOnce() async {
        guard let am = accountManager, let activeID = am.activeAccountID else { return }
        await refresh(accountID: activeID)
    }

    func refreshAllOnce() async {
        guard let am = accountManager else { return }
        for acc in am.accounts {
            await refresh(accountID: acc.id)
        }
    }

    // MARK: - private

    private func loadCachedSnapshots() {
        guard let am = accountManager else { return }
        for acc in am.accounts {
            if let s = try? snapshotStore.readUsage(for: acc.id) {
                snapshots[acc.id] = s
            }
        }
    }

    private func scheduleActive(every seconds: TimeInterval) {
        activeTimer?.invalidate()
        activeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshActiveOnce() }
        }
        if let t = activeTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func scheduleInactive(every seconds: TimeInterval) {
        inactiveTimer?.invalidate()
        inactiveTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshInactive() }
        }
        if let t = inactiveTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func refreshInactive() async {
        guard let am = accountManager else { return }
        for acc in am.accounts where acc.id != am.activeAccountID {
            await refresh(accountID: acc.id)
        }
    }

    private func refresh(accountID: AccountID) async {
        // backoff 존중
        if let next = nextEligibleAt[accountID], next > clock.now() {
            return
        }
        guard let snap = try? snapshotStore.read(for: accountID),
              let creds = try? JSON.decode(ClaudeCredentialsRoot.self, from: snap.credentialsJSON)
        else {
            return
        }
        let token = creds.claudeAiOauth.accessToken
        do {
            let usage = try await client.fetch(accessToken: token)
            snapshots[accountID] = usage
            lastError[accountID] = nil
            try? snapshotStore.writeUsage(usage, for: accountID)
        } catch UsageClientError.unauthorized {
            // 토큰 만료/무효 — 사용자에게 재로그인 안내. 주기적 재시도 차단.
            lastError[accountID] = "unauthorized"
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(15 * 60)
        } catch UsageClientError.rateLimited(let retry) {
            let wait = retry.flatMap { max($0, 30) } ?? 60
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(wait)
            lastError[accountID] = "rate_limited"
        } catch {
            lastError[accountID] = String(describing: error)
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(120)
        }
    }
}
