import Foundation

enum Paths {
    static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var claudeConfig: URL { home.appendingPathComponent(".claude.json") }
    static var claudeCredentials: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }

    static var appRoot: URL { home.appendingPathComponent(".cc-account-manager") }
    static var accountsFile: URL { appRoot.appendingPathComponent("accounts.json") }
    static var settingsFile: URL { appRoot.appendingPathComponent("settings.json") }
    static var snapshotsDir: URL { appRoot.appendingPathComponent("snapshots") }
    static var backupsDir: URL { appRoot.appendingPathComponent("backups") }
    static var lockFile: URL { appRoot.appendingPathComponent(".lock") }
    static var appInstanceLockFile: URL { appRoot.appendingPathComponent(".app.lock") }

    static func snapshotDir(for id: AccountID) -> URL {
        snapshotsDir.appendingPathComponent(id, isDirectory: true)
    }
}
