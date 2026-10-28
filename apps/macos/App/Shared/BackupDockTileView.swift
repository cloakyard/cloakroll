import AppKit

/// CloakDrop's white-on-dark Dock ring, adapted for one backup with honest whole-byte progress.
final class BackupDockTileView: NSView {
    var state = BackupDockState(percent: nil, isStopping: false)

    override func draw(_ dirtyRect: NSRect) {
        guard let icon = NSApplication.shared.applicationIconImage else { return }
        icon.draw(in: bounds)
        let iconSide = min(bounds.width, bounds.height) * 0.80
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let discRadius = iconSide * 0.46
        NSColor.black.withAlphaComponent(0.66).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - discRadius, y: center.y - discRadius,
                                   width: discRadius * 2, height: discRadius * 2)).fill()
        let diameter = iconSide * 0.60
        let lineWidth = iconSide * 0.11
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                              width: diameter, height: diameter))
        track.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.28).setStroke()
        track.stroke()
        if let percent = state.percent, percent > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: diameter / 2, startAngle: 90,
                          endAngle: 90 - CGFloat(percent) * 3.6, clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            NSColor.white.setStroke()
            arc.stroke()
        }
        let text = (state.percent.map { "\($0)%" } ?? "…") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: iconSide * 0.20, weight: .heavy),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }
}
