import Foundation

public enum PanelPlacement {
    public static func clamp(_ origin: CGPoint, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)),
                y: min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)))
    }

    public static func origin(panelSize: CGSize, fieldRect: CGRect, visibleFrame: CGRect,
                              gap: CGFloat = 12) -> CGPoint {
        let middleY = fieldRect.midY - panelSize.height / 2
        let candidates = [
            CGPoint(x: fieldRect.maxX + gap, y: middleY),
            CGPoint(x: fieldRect.minX - gap - panelSize.width, y: middleY),
            CGPoint(x: fieldRect.minX, y: fieldRect.maxY + gap),
            CGPoint(x: fieldRect.minX, y: fieldRect.minY - gap - panelSize.height)
        ]
        let placed = candidates.map { clamp($0, panelSize: panelSize, visibleFrame: visibleFrame) }
        if let clear = placed.first(where: { CGRect(origin: $0, size: panelSize).intersection(fieldRect).isNull }) {
            return clear
        }
        return placed.min {
            overlapArea(CGRect(origin: $0, size: panelSize), fieldRect)
                < overlapArea(CGRect(origin: $1, size: panelSize), fieldRect)
        } ?? clamp(CGPoint(x: fieldRect.maxX + gap, y: middleY), panelSize: panelSize, visibleFrame: visibleFrame)
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
