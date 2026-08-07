import AppKit
import ImageIO
import SwiftUI
import TwistKit
import UniformTypeIdentifiers

/// Renders the game's screens to PNGs without a display, so layout can be checked in both
/// appearances from a build step rather than by eye.
///
/// `Twist --snapshot <directory>` writes the images and exits.
@MainActor
enum Snapshot {
    static var requestedDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot") else { return nil }
        let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "build/snapshots"
        return URL(fileURLWithPath: path)
    }

    static var requestedSoundDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--export-sounds") else { return nil }
        let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "build/sounds"
        return URL(fileURLWithPath: path)
    }

    static func exportSounds(into directory: URL) -> Never {
        let engine = SoundEngine()
        do {
            try engine.export(to: directory)
            for cue in engine.measurements() {
                print("  \(cue.name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(cue.seconds.formatted(.number.precision(.fractionLength(2))))s  peak \(cue.peak.formatted(.number.precision(.fractionLength(3))))")
            }
            print("wrote sounds to \(directory.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("sound export failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(into directory: URL) -> Never {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let lexicon = LexiconLoader.loadBundled()

            for scheme in [ColorScheme.light, .dark] {
                let name = scheme == .light ? "light" : "dark"
                try write(
                    GameView(model: playedModel(lexicon: lexicon)),
                    size: CGSize(width: 760, height: 700),
                    scheme: scheme,
                    to: directory.appendingPathComponent("game-\(name).png"))
                try write(
                    ReviewView(model: reviewedModel(lexicon: lexicon)),
                    size: CGSize(width: 520, height: 560),
                    scheme: scheme,
                    to: directory.appendingPathComponent("review-\(name).png"))
                try write(
                    StatsView(model: modelWithHistory(lexicon: lexicon)),
                    size: CGSize(width: 460, height: 520),
                    scheme: scheme,
                    to: directory.appendingPathComponent("stats-\(name).png"))
                try write(
                    GameOverView(model: finishedModel(lexicon: lexicon)),
                    size: CGSize(width: 480, height: 520),
                    scheme: scheme,
                    to: directory.appendingPathComponent("gameover-\(name).png"))
            }
            print("wrote snapshots to \(directory.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    // MARK: - Fixtures

    /// Plays words through the real input path rather than reaching into the session, so a
    /// snapshot also exercises typing and submission.
    private static func play(_ words: some Sequence<String>, on model: GameModel) {
        for word in words {
            for character in word { model.type(character) }
            model.submit()
        }
    }

    /// A round part-way through, so found and unfound slots both appear.
    private static func playedModel(lexicon: Lexicon) -> GameModel {
        let model = GameModel(
            lexicon: lexicon,
            settings: GameSettings(clock: .timed(seconds: 120), rackSizes: [6]))
        let solutions = model.round.solutions.filter(\.isCommon).sorted { $0.word < $1.word }
        play(solutions.prefix(max(1, solutions.count / 3)).map(\.word), on: model)
        // Leave a few letters staged, so the input line is not empty in the image.
        for character in model.round.tiles.prefix(3) { model.type(character) }
        return model
    }

    /// A round ended without the full-rack word — the review screen worth checking, because
    /// it is the one carrying the missed-word list.
    private static func reviewedModel(lexicon: Lexicon) -> GameModel {
        let model = GameModel(
            lexicon: lexicon,
            settings: GameSettings(clock: .timed(seconds: 120), rackSizes: [6]))
        play(model.round.solutions.filter { $0.word.count == 3 }.prefix(2).map(\.word), on: model)
        model.endRound()
        return model
    }

    /// A model backed by a throwaway history file, so the stats screens have something to
    /// show without touching the real one in Application Support.
    private static func modelWithHistory(lexicon: Lexicon) -> GameModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("twist-snapshot-\(UUID().uuidString)/history.json")
        let store = HistoryStore(fileURL: url)
        let scores = [3_240, 11_800, 6_450, 18_900, 8_120, 14_300]
        try? store.save(scores.enumerated().map { index, score in
            GameRecord(
                finishedAt: Date().addingTimeInterval(Double(index - scores.count) * 86_400),
                score: score,
                roundsCleared: 2 + index % 4,
                roundsCompleted: index % 2,
                wordsFound: 18 + index * 7,
                bingosFound: 2 + index % 4,
                rackSizes: index.isMultiple(of: 2) ? [6, 6] : [7, 7],
                wasTimed: true)
        })
        return GameModel(
            lexicon: lexicon,
            settings: GameSettings(clock: .timed(seconds: 120), rackSizes: [6]),
            store: store)
    }

    /// A sitting that has ended, for the game-over screen.
    private static func finishedModel(lexicon: Lexicon) -> GameModel {
        let model = modelWithHistory(lexicon: lexicon)
        play(model.round.solutions.filter { $0.word.count == 3 }.prefix(3).map(\.word), on: model)
        model.endRound()
        model.advance()  // no full-rack word, so this ends the sitting
        return model
    }

    private static func write(
        _ view: some View, size: CGSize, scheme: ColorScheme, to url: URL
    ) throws {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                // Must match TwistApp, or the snapshots verify a different-looking app.
                .tint(Theme.accent)
                .environment(\.isSnapshotting, true)
                .environment(\.colorScheme, scheme)
                .background(Theme.background)
        )
        renderer.scale = 2

        guard let image = renderer.cgImage,
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
