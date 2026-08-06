import SwiftUI

/// Lays subviews out left to right, wrapping to a new line when the next one will not fit.
///
/// `LazyVGrid(.adaptive)` was the obvious choice and the wrong one twice over: it pads every
/// column to the widest item, so a row of three-letter slots sprawls to six-letter width, and
/// being lazy it materialises nothing under `ImageRenderer`, which is how the snapshots came
/// out blank. Word counts here top out in the dozens, so laziness buys nothing anyway.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let lines = layout(subviews: subviews, in: width)
        guard let last = lines.last else { return .zero }
        return CGSize(width: width, height: last.y + last.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for line in layout(subviews: subviews, in: bounds.width) {
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + line.y),
                    proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct Line {
        var y: CGFloat
        var height: CGFloat
        var items: [(index: Int, x: CGFloat, size: CGSize)]
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line(y: 0, height: 0, items: [])
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                lines.append(current)
                current = Line(y: current.y + current.height + lineSpacing, height: 0, items: [])
                x = 0
            }
            current.items.append((index: index, x: x, size: size))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { lines.append(current) }
        return lines
    }
}
