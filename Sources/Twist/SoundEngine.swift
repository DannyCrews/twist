import AVFoundation
import Foundation

/// The game's voice: soft struck-bar tones, synthesized at launch.
///
/// Everything is generated rather than shipped, which keeps the bundle tiny and sidesteps
/// sample licensing entirely. The design goal is calm — this is a game you play to unwind, and
/// a word game punishes you often enough without the audio joining in:
///
/// * Every pitch comes from one **pentatonic scale**, so no two cues can ever clash, however
///   they overlap.
/// * Tones are **sine fundamentals with two quiet harmonics that decay faster** than the
///   fundamental, which is roughly what a struck wooden bar does — warm, never buzzy.
/// * Envelopes have a **soft attack** (no click at onset) and a **long exponential release**.
/// * A rejected word is a *low, quiet, short* note, not a buzzer. It should read as "not that
///   one" rather than "wrong".
@MainActor
final class SoundEngine {
    enum Cue {
        case tile          // a letter staged
        case word
        case bingo
        case reject
        case twist
        case roundComplete
        case timeLow
    }

    var isEnabled = true

    /// Deliberately low. This should sit under the room, not on top of it.
    var volume: Float = 0.22 {
        didSet { mixer.outputVolume = volume }
    }

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var isRunning = false

    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    /// C-major pentatonic, one octave up from middle C. Any subset of these sounds consonant
    /// together, which is what lets cues overlap without ever souring.
    private static let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50]

    init() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        mixer.outputVolume = volume

        // A small pool, so a fast typist's cues overlap instead of cutting each other off.
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            players.append(player)
        }

        renderBuffers()

        do {
            try engine.start()
            for player in players { player.play() }
            isRunning = true
        } catch {
            // Audio is a nicety. A machine that will not give us an output node still plays
            // the game fine.
            isRunning = false
        }
    }

    func play(_ cue: Cue) {
        guard isEnabled, isRunning, let buffer = buffers[key(for: cue)] else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// Writes every cue to a WAV, so the sound design can be listened to and measured rather
    /// than taken on trust. `Twist --export-sounds <directory>`.
    func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, buffer) in buffers.sorted(by: { $0.key < $1.key }) {
            let url = directory.appendingPathComponent("\(name).wav")
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                ])
            try file.write(from: buffer)
        }
    }

    /// Peak level and duration per cue, for checking nothing clips or runs long.
    func measurements() -> [(name: String, seconds: Double, peak: Float)] {
        buffers.sorted { $0.key < $1.key }.map { name, buffer in
            var peak: Float = 0
            if let samples = buffer.floatChannelData?[0] {
                for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[index])) }
            }
            return (name, Double(buffer.frameLength) / format.sampleRate, peak)
        }
    }

    // MARK: - Synthesis

    private func key(for cue: Cue) -> String {
        switch cue {
        case .tile: "tile"
        case .word: "word"
        case .bingo: "bingo"
        case .reject: "reject"
        case .twist: "twist"
        case .roundComplete: "complete"
        case .timeLow: "timeLow"
        }
    }

    private func renderBuffers() {
        // Staging a letter happens constantly, so it is the quietest thing here: a brief,
        // high, almost-subliminal tick.
        buffers["tile"] = render(notes: [Note(frequency: 1174.66, start: 0, duration: 0.09, gain: 0.10)])

        // Success: a chime. One strike, bell partials.
        //
        // The ratios are a struck metal bar's, not a harmonic series — 2.76 and 5.4 are what
        // make it read as a bell rather than a flute. The fundamental decays slowly while the
        // upper partials fall away fast, which is the shimmer.
        //
        // One sound for every accepted word, whatever its length. This used to climb the scale
        // with word length, which sounded expressive and was a mistake: all five pitches meant
        // the same thing, so the variation carried nothing actionable while making the cue
        // ambiguous enough that you looked at the screen to check — the exact work an audio cue
        // exists to save.
        buffers["word"] = render(notes: [
            Note(
                frequency: 880.00, start: 0, duration: 0.85, gain: 0.42, attack: 0.006,
                partials: [
                    (1.00, 1.00, 0.6), (2.76, 0.42, 2.2),
                    (5.40, 0.16, 3.4), (8.93, 0.06, 4.6),
                ])
        ])

        // The full-rack word: three bell strikes rising. Always also a success, so it never
        // makes "was I right?" ambiguous — it marks a different event, not a different degree
        // of correctness.
        let bell: [(ratio: Double, gain: Double, decay: Double)] = [
            (1.00, 1.00, 0.6), (2.76, 0.38, 2.2), (5.40, 0.12, 3.4),
        ]
        buffers["bingo"] = render(notes: [
            Note(frequency: 659.25, start: 0.00, duration: 0.9, gain: 0.34,
                 attack: 0.006, partials: bell),
            Note(frequency: 880.00, start: 0.11, duration: 0.9, gain: 0.34,
                 attack: 0.006, partials: bell),
            Note(frequency: 1046.50, start: 0.22, duration: 1.1, gain: 0.38,
                 attack: 0.006, partials: bell),
        ])

        // Failure: a soft gong. Low, slow to speak, long to fade.
        //
        // Inharmonic partials again, spaced the way a struck plate rings. Kept at G3 rather
        // than anything lower because laptop speakers roll off below roughly 200 Hz and ears
        // discount low frequencies anyway — a truly low gong would simply not arrive.
        //
        // Still not a buzzer. It should land as "not that one", not as a reprimand.
        buffers["reject"] = render(notes: [
            Note(
                frequency: 196.00, start: 0, duration: 1.1, gain: 0.36, attack: 0.05,
                partials: [
                    (1.00, 1.00, 0.5), (1.48, 0.55, 1.4), (2.13, 0.34, 2.0),
                    (2.87, 0.20, 2.8), (3.76, 0.10, 3.6),
                ])
        ])

        // Twisting is airy — two soft notes a fifth apart, felt more than heard.
        buffers["twist"] = render(notes: [
            Note(frequency: 659.25, start: 0.00, duration: 0.22, gain: 0.16),
            Note(frequency: 987.77, start: 0.04, duration: 0.26, gain: 0.13),
        ])

        // Clearing the board: a warm, open chord that rings out.
        buffers["complete"] = render(notes: [
            Note(frequency: 523.25, start: 0.00, duration: 1.3, gain: 0.34),
            Note(frequency: 659.25, start: 0.05, duration: 1.3, gain: 0.30),
            Note(frequency: 783.99, start: 0.10, duration: 1.3, gain: 0.30),
            Note(frequency: 1046.50, start: 0.15, duration: 1.4, gain: 0.26),
        ])

        // Time running out: still one soft note, never a clock tick — nothing raises a pulse
        // rate like being ticked at.
        //
        // G4 rather than the G3 this started on. K-weighted measurement put the low version at
        // −26.8 LUFS: quieter than the rejection sound and 11 LU under the word cues, because
        // ears discount low frequencies heavily and its respectable −13 dBFS peak hid that.
        // The one cue whose whole job is to be noticed was the least audible thing in the game.
        // An octave up buys audibility without making it loud.
        buffers["timeLow"] = render(notes: [Note(frequency: 392.00, start: 0, duration: 0.5, gain: 0.30)])
    }

    /// One struck sound. `partials` are frequency ratios against the fundamental, each with a
    /// gain and a decay exponent — a higher exponent fades faster.
    ///
    /// Ratios rather than harmonics because bells and gongs are not harmonic. A struck metal
    /// body rings at frequencies that are not integer multiples of anything, and that
    /// inharmonicity *is* the sound; forcing 2x and 3x gives an organ, not a chime.
    private struct Note {
        let frequency: Double
        let start: Double
        let duration: Double
        let gain: Double
        var attack: Double = 0.14
        var partials: [(ratio: Double, gain: Double, decay: Double)] = [
            (1.0, 1.00, 0), (2.0, 0.28, 2), (3.0, 0.10, 3),
        ]
    }

    private func render(notes: [Note]) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let total = notes.map { $0.start + $0.duration }.max() ?? 0
        let frameCount = AVAudioFrameCount(total * sampleRate)
        guard frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        for index in 0..<Int(frameCount) { samples[index] = 0 }

        for note in notes {
            let firstFrame = Int(note.start * sampleRate)
            let noteFrames = Int(note.duration * sampleRate)

            for offset in 0..<noteFrames {
                let frame = firstFrame + offset
                guard frame < Int(frameCount) else { break }
                let progress = Double(offset) / Double(noteFrames)

                var value = 0.0
                for partial in note.partials {
                    let phase =
                        2 * Double.pi * note.frequency * partial.ratio / sampleRate
                        * Double(offset)
                    let fade = partial.decay > 0 ? pow(1 - progress, partial.decay) : 1
                    value += partial.gain * sin(phase) * fade
                }
                samples[frame] += Float(
                    value * envelope(at: progress, frames: noteFrames, attack: note.attack)
                        * note.gain)
            }
        }

        // Guard against summed partials clipping.
        var peak: Float = 0
        for index in 0..<Int(frameCount) { peak = max(peak, abs(samples[index])) }
        if peak > 0.95 {
            let scale = 0.95 / peak
            for index in 0..<Int(frameCount) { samples[index] *= scale }
        }
        return buffer
    }

    /// Raised-cosine attack into an exponential release. The attack matters most: a hard onset
    /// is heard as a click no matter how gentle the tone behind it.
    private func envelope(at progress: Double, frames: Int, attack requested: Double) -> Double {
        let attack = min(requested, max(0.002, 480.0 / Double(frames)))
        if progress < attack {
            return 0.5 * (1 - cos(.pi * progress / attack))
        }
        let releaseProgress = (progress - attack) / (1 - attack)
        return exp(-4.2 * releaseProgress)
    }
}
