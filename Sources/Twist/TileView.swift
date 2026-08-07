import SwiftUI

/// A letter tile, in the rack or in the input line.
///
/// Sized and tuned for a trackpad rather than a mouse. A trackpad gives you less precision and
/// no resting cursor, so the tile is large, its whole rectangle is clickable rather than just
/// the glyph, and hover response is quick but eased — a linear or instant hover reads as
/// twitchy when the pointer is drifting the way a trackpad pointer does.
struct TileView: View {
    enum Role {
        case rack       // available to click
        case staged     // spoken for; the gap left behind in the rack
        case entry      // sitting in the input line
        case empty      // an unfilled slot in the input line
    }

    let letter: Character?
    let role: Role
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

    private var size: CGSize {
        switch role {
        case .rack, .staged: CGSize(width: 54, height: 64)
        case .entry, .empty: CGSize(width: 40, height: 50)
        }
    }

    private var isInteractive: Bool { role == .rack && action != nil }

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isHovering ? Theme.accent.opacity(0.55) : Theme.hairline,
                        lineWidth: 1)
            }
            .overlay {
                Text(letter.map { String($0).uppercased() } ?? "")
                    .font(.system(size: role == .rack ? 30 : 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        role == .staged
                            ? AnyShapeStyle(.clear)
                            : AnyShapeStyle(role == .entry ? Theme.accent : Theme.textPrimary))
            }
            .frame(width: size.width, height: size.height)
            // The whole rectangle is the target, not just the letter inside it.
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(scale)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16, extraBounce: 0.1), value: isHovering)
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: isPressed)

        Group {
            if isInteractive {
                tile
                    .onHover { isHovering = $0 }
                    .pointerStyle(.link)
                    .onTapGesture { action?() }
                    // A press gesture rather than a Button: it gives the tile a pressed state
                    // without a Button's own highlight fighting the one drawn here.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isPressed = true }
                            .onEnded { _ in isPressed = false }
                    )
            } else {
                tile
            }
        }
    }

    private var fill: AnyShapeStyle {
        switch role {
        case .rack: AnyShapeStyle(isHovering ? Theme.tileHover : Theme.tile)
        case .staged: AnyShapeStyle(Theme.slot)
        case .entry: AnyShapeStyle(Theme.accentSoft)
        case .empty: AnyShapeStyle(Theme.slot)
        }
    }

    private var scale: CGFloat {
        if isPressed { return 0.94 }
        return isHovering ? 1.04 : 1.0
    }
}


/// Twist and Enter.
///
/// A custom style rather than `.bordered` at `.controlSize(.extraLarge)`: the system styles
/// draw at their own intrinsic size and ignore an outer `.frame`, so the measured hit region
/// stayed at 36 pt tall no matter what was asked for. Apple's HIG asks for a 44 pt hit region
/// and WCAG 2.5.5 sets the same figure at AAA, so the size is stated here and drawn here.
struct PrimaryButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .font(.body.weight(.semibold))
            .frame(width: 140, height: 48)
            // Text in the page colour on an accent fill: measured at 6.4:1 in light and 7.1:1
            // in dark, so it holds in both without a per-scheme special case.
            .foregroundStyle(isProminent ? Theme.background : Theme.textPrimary)
            .background(shape.fill(isProminent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.tile)))
            .overlay(shape.strokeBorder(isProminent ? Color.clear : Theme.hairline, lineWidth: 1))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
