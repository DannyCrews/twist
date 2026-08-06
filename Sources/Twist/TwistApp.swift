import SwiftUI
import TwistKit

@main
struct TwistApp: App {
    @State private var model = GameModel(lexicon: LexiconLoader.loadBundled())

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
            GameView(model: model)
                .frame(minWidth: 720, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Game") { model.restart() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .toolbar) {
                Button("Statistics") {
                    NotificationCenter.default.post(name: .showStatistics, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}
