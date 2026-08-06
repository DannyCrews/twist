import Foundation
import TwistKit

enum LexiconLoader {
    /// Loads the lexicon shipped in the app bundle.
    ///
    /// A missing or malformed resource is a build error that escaped, not something a player
    /// can do anything about, so it fails loudly rather than starting a game with no words.
    static func loadBundled() -> Lexicon {
        // `Contents/Resources` in a packaged app, `Twist_Twist.bundle` under `swift run`.
        // The packaged app copies the file in flat rather than nesting SwiftPM's resource
        // bundle, because that bundle carries no Info.plist and codesign rejects it as a
        // subcomponent — which failed the build script silently under `set -e`.
        let url = Bundle.main.url(forResource: "lexicon", withExtension: "twist")
            ?? Bundle.module.url(forResource: "lexicon", withExtension: "twist")
        guard let url else {
            fatalError("lexicon.twist is missing from the app bundle — run `make dict`")
        }
        do {
            return try LexiconFile.decode(try String(contentsOf: url, encoding: .utf8))
        } catch {
            fatalError("lexicon.twist could not be read: \(error)")
        }
    }
}
