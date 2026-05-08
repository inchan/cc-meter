import AppKit

enum StatusIconRenderer {
    /// 메뉴바용 이니셜 + 색상 원형 아이콘 (단독 사용).
    static func render(initial: String, hex: String, size: CGFloat = 18) -> NSImage {
        let pxSize = NSSize(width: size, height: size)
        let image = NSImage(size: pxSize)
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }
        drawCircle(initial: initial, hex: hex, in: NSRect(origin: .zero, size: pxSize))
        image.isTemplate = false
        return image
    }

    /// 메뉴바 풀 라벨: [원형 이니셜] S: NN%  W: NN% (색상 포함, monochrome 회피)
    static func renderStatusBar(initial: String,
                                hex: String,
                                fiveHour: Int?,
                                fiveLevel: ThresholdLevel?,
                                sevenDay: Int?,
                                sevenLevel: ThresholdLevel?) -> NSImage {
        // 메뉴바 슬롯 높이는 22pt. 이미지 height 를 동일하게 맞춰야 시스템이
        // 자동 위쪽 정렬을 하지 않는다. 원형 아이콘은 18pt 유지하고 22pt 안에서 가운데.
        let height: CGFloat = 22
        let circleSize: CGFloat = 18
        let gap: CGFloat = 8
        let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let secondary = NSColor.secondaryLabelColor

        // 텍스트 조각 구성. "S: 52%" 전체가 임계치 색으로 통일되도록 단일 piece.
        var pieces: [(String, NSColor)] = []
        if let fh = fiveHour, let lv = fiveLevel {
            pieces.append(("S: \(fh)%", lv.nsColor))
        }
        if let sd = sevenDay, let lv = sevenLevel {
            pieces.append(("  W: \(sd)%", lv.nsColor))
        }
        if pieces.isEmpty {
            pieces.append((" --", secondary))
        }

        let attrs: [(NSAttributedString, NSSize)] = pieces.map { piece in
            let a = NSAttributedString(string: piece.0, attributes: [
                .font: labelFont, .foregroundColor: piece.1
            ])
            return (a, a.size())
        }
        let textWidth = attrs.reduce(CGFloat(0)) { $0 + $1.1.width }
        let totalWidth = circleSize + gap + textWidth + 2

        // lockFocus 패턴 폐기 — drawingHandler 가 alpha/리텐션이 안정적.
        let image = NSImage(size: NSSize(width: totalWidth, height: height),
                            flipped: false) { _ in
            let circleY = (height - circleSize) / 2
            drawCircle(initial: initial, hex: hex,
                       in: NSRect(x: 0, y: circleY,
                                  width: circleSize, height: circleSize))

            let textBoxHeight = attrs.first?.1.height
                ?? (labelFont.ascender - labelFont.descender)
            let textY = (height - textBoxHeight) / 2
            var x: CGFloat = circleSize + gap
            for (attr, size) in attrs {
                attr.draw(at: NSPoint(x: x, y: textY))
                x += size.width
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - private

    private static func drawCircle(initial: String, hex: String, in rect: NSRect) {
        let fillColor = NSColor(hex: hex) ?? .systemBlue
        fillColor.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: rect.height * 0.55, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: initial, attributes: attrs)
        let size = text.size()
        let textRect = NSRect(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: textRect)
    }
}

extension ThresholdLevel {
    /// AppKit 색 (NSImage 그리기에 사용)
    var nsColor: NSColor {
        switch self {
        case .healthy: return .systemGreen
        case .caution: return .systemYellow
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
