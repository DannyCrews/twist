import SwiftUI
import TwistKit

@main
struct TwistApp: App {
    @State private var app = AppModel(lexicon: LexiconLoader.loadBundled())

    // Dark by default. The palette is built for it, and a white field behind a running clock
    // is tiring however good the colours on top of it are.
    @AppStorage("Appearance") private var appearance: Appearance = .dark

    init() {
        if let directory = Snapshot.requestedDirectory {
            Snapshot.run(into: directory)
        }
        if let directory = Snapshot.requestedSoundDirectory {
            Snapshot.exportSounds(into: directory)
        }
    }

    var body: some Scene {
        WindowGroup("Twist") {
            RootView(app: app)
                .frame(minWidth: 760, minHeight: 780)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Game") { app.returnToMenu() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .toolbar) {
                Button("Statistics") {
                    NotificationCenter.default.post(name: .showStatistics, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }
}

/// Switches between the menu and a game in progress.
struct RootView: View {
    @Bindable var app: AppModel

    var body: some View {
        if let game = app.game {
            GameView(model: game, onQuit: { app.returnToMenu() })
        } else {
            StartView(app: app)
        }
    }
}
