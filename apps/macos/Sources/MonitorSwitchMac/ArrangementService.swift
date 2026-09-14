import Foundation
import CoreGraphics
import AppKit

public struct DisplayPlacement: Identifiable, Equatable {
    public let id: CGDirectDisplayID
    public let name: String
    public let bounds: CGRect
    public let isMain: Bool
    public let isBuiltin: Bool

    public var width: CGFloat { bounds.width }
    public var height: CGFloat { bounds.height }
}

@MainActor
public final class ArrangementService: ObservableObject {
    public static let shared = ArrangementService()

    @Published public private(set) var placements: [DisplayPlacement] = []
    @Published public var draggedID: CGDirectDisplayID? = nil
    @Published public var dragOffset: CGSize = .zero

    private init() {
        refresh()
    }

    public func refresh() {
        let maxDisplays: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0

        guard CGGetActiveDisplayList(maxDisplays, &activeDisplays, &count) == .success else { return }

        var list: [DisplayPlacement] = []
        for i in 0..<Int(count) {
            let id = activeDisplays[i]
            let bounds = CGDisplayBounds(id)
            let isMain = CGDisplayIsMain(id) != 0
            let isBuiltin = CGDisplayIsBuiltin(id) != 0

            var name = isBuiltin ? "内建显示器" : "外接显示器"
            for screen in NSScreen.screens {
                if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                   num == id {
                    name = screen.localizedName
                    break
                }
            }

            list.append(DisplayPlacement(
                id: id,
                name: name,
                bounds: bounds,
                isMain: isMain,
                isBuiltin: isBuiltin
            ))
        }

        self.placements = list
    }

    /// Moves a specific display to (x, y) coordinates and renormalizes with main at (0, 0)
    @discardableResult
    public func setPosition(x: Int, y: Int, for displayID: CGDirectDisplayID) -> Bool {
        refresh()
        var origins: [(id: CGDirectDisplayID, x: Int, y: Int)] = placements.map { d in
            d.id == displayID
                ? (d.id, x, y)
                : (d.id, Int(d.bounds.origin.x), Int(d.bounds.origin.y))
        }

        // Renormalize so current main sits at (0, 0)
        if let mainID = placements.first(where: { $0.isMain })?.id,
           let main = origins.first(where: { $0.id == mainID }),
           main.x != 0 || main.y != 0 {
            let dx = main.x, dy = main.y
            origins = origins.map { ($0.id, $0.x - dx, $0.y - dy) }
        }

        let success = applyOrigins(origins)
        if success {
            refresh()
        }
        return success
    }

    /// Interactive drag: converts canvas translation to global screen points, resolves overlaps, and applies
    @discardableResult
    public func applyDrag(for id: CGDirectDisplayID, translation: CGSize, scale: CGFloat) -> Bool {
        guard scale > 0, let display = placements.first(where: { $0.id == id }) else { return false }
        let proposed = display.bounds.offsetBy(dx: translation.width / scale, dy: translation.height / scale)
        let others = placements.filter { $0.id != id }.map { $0.bounds }

        let resolved = resolveOverlaps(proposed, others: others)
        let snapped = snappedRect(resolved, others: others, threshold: 40 / scale)

        let newX = Int(snapped.minX.rounded())
        let newY = Int(snapped.minY.rounded())

        return setPosition(x: newX, y: newY, for: id)
    }

    /// Set a specific display as the main display (Dock & Menu bar)
    @discardableResult
    public func setAsMainDisplay(targetID: CGDirectDisplayID) -> Bool {
        refresh()
        guard let target = placements.first(where: { $0.id == targetID }), !target.isMain else {
            return false
        }

        let dx = Int(target.bounds.origin.x)
        let dy = Int(target.bounds.origin.y)

        let origins: [(id: CGDirectDisplayID, x: Int, y: Int)] = placements.map {
            ($0.id, Int($0.bounds.origin.x) - dx, Int($0.bounds.origin.y) - dy)
        }

        let success = applyOrigins(origins)
        if success {
            refresh()
        }
        return success
    }

    /// Atomically apply origins to macOS WindowServer
    private func applyOrigins(_ origins: [(id: CGDirectDisplayID, x: Int, y: Int)]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,
              let cfg = config else { return false }

        for item in origins {
            CGConfigureDisplayOrigin(cfg, item.id, Int32(item.x), Int32(item.y))
        }

        let result = CGCompleteDisplayConfiguration(cfg, .forSession)
        if result != .success {
            CGCancelDisplayConfiguration(cfg)
            return false
        }
        return true
    }

    // MARK: - Snapping & Overlap Math

    private func snappedRect(_ rect: CGRect, others: [CGRect], threshold: CGFloat) -> CGRect {
        var r = rect
        var bestDX = CGFloat.infinity
        var partnerX: CGRect?
        var bestDY = CGFloat.infinity
        var partnerY: CGRect?

        for o in others {
            for dx in [o.maxX - r.minX, o.minX - r.maxX] where abs(dx) < abs(bestDX) {
                bestDX = dx
                partnerX = o
            }
            for dy in [o.maxY - r.minY, o.minY - r.maxY] where abs(dy) < abs(bestDY) {
                bestDY = dy
                partnerY = o
            }
        }

        let canX = abs(bestDX) <= threshold
        let canY = abs(bestDY) <= threshold

        if canX && (!canY || abs(bestDX) <= abs(bestDY)) {
            r.origin.x += bestDX
            if let o = partnerX,
               let align = [o.minY - r.minY, o.maxY - r.maxY].min(by: { abs($0) < abs($1) }),
               abs(align) <= threshold {
                r.origin.y += align
            }
        } else if canY {
            r.origin.y += bestDY
            if let o = partnerY,
               let align = [o.minX - r.minX, o.maxX - r.maxX].min(by: { abs($0) < abs($1) }),
               abs(align) <= threshold {
                r.origin.x += align
            }
        }
        return r
    }

    private func resolveOverlaps(_ rect: CGRect, others: [CGRect]) -> CGRect {
        var r = rect
        for _ in 0..<32 {
            guard let o = others.first(where: { overlapExtents($0, r) != nil }) else { break }
            r = snapToDominantSide(r, of: o)
        }
        return r
    }

    private func snapToDominantSide(_ r: CGRect, of o: CGRect) -> CGRect {
        var out = r
        let dx = r.midX - o.midX
        let dy = r.midY - o.midY
        let verticalPullFloor = min(r.height, o.height) * 0.45
        if abs(dy) > abs(dx) * 1.5 && abs(dy) > verticalPullFloor {
            out.origin.y = dy >= 0 ? o.maxY : o.minY - r.height
        } else {
            out.origin.x = dx >= 0 ? o.maxX : o.minX - r.width
        }
        return out
    }

    private func overlapExtents(_ a: CGRect, _ b: CGRect) -> (x: CGFloat, y: CGFloat)? {
        let ox = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let oy = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return (ox > 0 && oy > 0) ? (ox, oy) : nil
    }
}
