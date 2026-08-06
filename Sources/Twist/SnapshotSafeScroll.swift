import SwiftUI

/// True while `Twist --snapshot` is rendering. Views should not change what they look like
/// based on this — it exists only to route around `ImageRenderer` limitations.
///
/// Spelled out longhand rather than with `@Entry`: that macro's plugin ships with Xcode, and
/// this package builds against the Command Line Tools alone.
private struct SnapshottingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshotting: Bool {
        get { self[SnapshottingKey.self] }
        set { self[SnapshottingKey.self] = newValue }
    }
}

/// A `ScrollView` that becomes a plain stack while snapshotting.
///
/// `ImageRenderer` lays out without a hosting window, and a `ScrollView` given no window
/// produces no content at all — the first snapshots came back with an empty board and an empty
/// missed-word list for exactly this reason. Collapsing to a stack renders the same content at
/// the same size, so the images still verify the layout that ships.
struct ScrollIfNeeded<Content: View>: View {
    @Environment(\.isSnapshotting) private var isSnapshotting
    @ViewBuilder var content: Content

    var body: some View {
        if isSnapshotting {
            content
        } else {
            ScrollView { content }
        }
    }
}
