import Foundation
import OSLog

enum Log {
    static let app = Logger(subsystem: "com.inchan.cc-account-manager", category: "app")
    static let store = Logger(subsystem: "com.inchan.cc-account-manager", category: "storage")
    static let switching = Logger(subsystem: "com.inchan.cc-account-manager", category: "switch")
    static let usage = Logger(subsystem: "com.inchan.cc-account-manager", category: "usage")
    static let ui = Logger(subsystem: "com.inchan.cc-account-manager", category: "ui")

    /// 토큰을 안전하게 마스킹. 길이/접두 노출 금지 — 짧은 토큰도 식별 불가.
    /// 안정성을 위해 결정적 해시(FNV-1a 32bit) 의 hex 8자만 노출.
    static func mask(_ token: String?) -> String {
        guard let t = token, !t.isEmpty else { return "<nil>" }
        var h: UInt32 = 0x811c9dc5
        for byte in t.utf8 {
            h ^= UInt32(byte)
            h &*= 0x01000193
        }
        return "<token:" + String(format: "%08x", h) + ">"
    }
}
