import Foundation
import Combine

/// 도메인 진입점. UI 와 Storage/ClaudeIntegration 사이의 facade.
@MainActor
final class AccountManager: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var activeAccountID: AccountID?
    @Published private(set) var lastError: String?

    private let repo: AccountRepositoryProtocol
    private let snapshots: ProfileSnapshotStoreProtocol
    private let configFile: ClaudeConfigFile
    private let credFile: ClaudeCredentialsFile
    private let processGuard: ClaudeProcessGuard
    private let backups: BackupRotator
    private let switcher: SwitchTransaction
    private let authCLI = ClaudeAuthCLI()

    init(repo: AccountRepositoryProtocol = AccountRepository(),
         snapshots: ProfileSnapshotStoreProtocol = ProfileSnapshotStore(),
         configFile: ClaudeConfigFile = ClaudeConfigFile(),
         credFile: ClaudeCredentialsFile = ClaudeCredentialsFile(),
         processGuard: ClaudeProcessGuard = ClaudeProcessGuard(),
         backups: BackupRotator = BackupRotator()) {
        self.repo = repo
        self.snapshots = snapshots
        self.configFile = configFile
        self.credFile = credFile
        self.processGuard = processGuard
        self.backups = backups
        self.switcher = SwitchTransaction(configFile: configFile,
                                          credFile: credFile,
                                          snapshotStore: snapshots,
                                          backups: backups,
                                          processGuard: processGuard,
                                          accountRepo: repo)
    }

    func reload() {
        do {
            accounts = try repo.load().sorted { ($0.lastUsedAt ?? $0.addedAt) > ($1.lastUsedAt ?? $1.addedAt) }
            activeAccountID = try detectActiveAccountID()
            lastError = nil
        } catch {
            lastError = String(describing: error)
            Log.app.error("reload failed: \(String(describing: error))")
        }
    }

    /// 현재 Claude Code 활성 계정을 import. 같은 accountUuid 가 이미 있으면 갱신.
    @discardableResult
    func importCurrent(label: String? = nil, colorHex: String? = nil) throws -> Account {
        let oauthData = try configFile.readOAuthAccountJSON()
        let credsData = try credFile.readRaw()
        let oauth = try JSON.decode(ClaudeOAuthAccount.self, from: oauthData)

        var accounts = try repo.load()
        if let idx = accounts.firstIndex(where: { $0.accountUuid == oauth.accountUuid }) {
            // 갱신
            var existing = accounts[idx]
            existing.lastUsedAt = Date()
            existing.label = label ?? existing.label
            if let c = colorHex { existing.colorHex = c }
            accounts[idx] = existing
            try repo.save(accounts)
            try snapshots.write(.init(oauthAccountJSON: oauthData, credentialsJSON: credsData),
                                for: existing.id)
            reload()
            notifyAccountChanged(id: existing.id, kind: .imported)
            return existing
        }

        let id = UUID().uuidString
        let acc = Account(
            id: id,
            label: label ?? defaultLabel(for: oauth.emailAddress),
            emailAddress: oauth.emailAddress,
            accountUuid: oauth.accountUuid,
            organizationUuid: oauth.organizationUuid,
            colorHex: colorHex ?? Account.deterministicColor(for: oauth.emailAddress.lowercased()),
            addedAt: Date(),
            lastUsedAt: Date(),
            subscriptionType: nil
        )
        accounts.append(acc)
        try repo.save(accounts)
        try snapshots.write(.init(oauthAccountJSON: oauthData, credentialsJSON: credsData), for: id)
        reload()
        notifyAccountChanged(id: id, kind: .imported)
        return acc
    }

    func remove(_ id: AccountID) throws {
        var accounts = try repo.load()
        accounts.removeAll { $0.id == id }
        try repo.save(accounts)
        try snapshots.remove(for: id)
        reload()
    }

    func rename(_ id: AccountID, to label: String) throws {
        var accounts = try repo.load()
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].label = label
        try repo.save(accounts)
        reload()
    }

    func switchTo(_ id: AccountID, allowWhileClaudeRunning: Bool = false) throws {
        try switcher.execute(targetID: id, allowWhileClaudeRunning: allowWhileClaudeRunning)
        reload()
        notifyAccountChanged(id: id, kind: .switched)
    }

    private func notifyAccountChanged(id: AccountID, kind: CCAccountChangedKind) {
        NotificationCenter.default.post(
            name: .ccAccountChanged,
            object: nil,
            userInfo: ["accountID": id, "kind": kind.rawValue]
        )
    }

    func openLogin() throws {
        try authCLI.launchLogin()
    }

    // MARK: - helpers

    private func defaultLabel(for email: String) -> String {
        if let local = email.split(separator: "@").first {
            return String(local)
        }
        return email
    }

    private func detectActiveAccountID() throws -> AccountID? {
        let oauth = try configFile.readOAuthAccount()
        return accounts.first { $0.accountUuid == oauth.accountUuid }?.id
    }
}

extension Account {
    /// 이메일(또는 임의 식별자) 기반 결정적 컬러. Swift Hasher 는 런타임 시드 랜덤화로
    /// 비결정적이므로 FNV-1a (32-bit) 로 안정화. 같은 입력 → 항상 같은 색.
    /// 이메일을 기준으로 하면 같은 이니셜의 다른 계정도 색으로 구분됨.
    static func deterministicColor(for seed: String) -> String {
        let palette = [
            "#3478F6", "#34C759", "#FF9500", "#FF3B30",
            "#AF52DE", "#5AC8FA", "#FF2D55", "#A2845E",
            "#30B0C7", "#BF5AF2"
        ]
        var h: UInt32 = 0x811c9dc5
        for byte in seed.utf8 {
            h ^= UInt32(byte)
            h &*= 0x01000193
        }
        return palette[Int(h % UInt32(palette.count))]
    }
}
