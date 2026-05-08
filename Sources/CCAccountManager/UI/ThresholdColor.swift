import SwiftUI

extension ThresholdLevel {
    /// 4단계 신호색.
    /// healthy < 50% (green) / caution ≥50% (yellow) / warning ≥80% (orange) / critical ≥95% (red).
    var color: Color {
        switch self {
        case .healthy: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
