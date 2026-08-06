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
        case word(length: Int)
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
        case .word(let length): "word\(min(max(length, 3), 7))"
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

        // Longer words climb the scale. Finding a five-letter word should feel better than a
        // three, before you even look at the score.
        for length in 3...7 {
            let degree = min(length - 3, Self.scale.count - 1)
            buffers["word\(length)"] = render(notes: [
                Note(frequency: Self.scale[degree], start: 0, duration: 0.45, gain: 0.5)
            ])
        }

        // The full-rack word: a rising three-note figure, the one genuinely celebratory sound.
        buffers["bingo"] = render(notes: [
            Note(frequency: Self.scale[0], start: 0.00, duration: 0.55, gain: 0.45),
            Note(frequency: Self.scale[2], start: 0.09, duration: 0.55, gain: 0.45),
            Note(frequency: Self.scale[4], start: 0.18, duration: 0.75, gain: 0.50),
        ])

        // Not a buzzer: one low, quiet, quickly-gone note.
        buffers["reject"] = render(notes: [Note(frequency: 261.63, start: 0, duration: 0.18, gain: 0.22)])

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

        // Time running out is a low, soft pulse. Never a clock tick — nothing raises a pulse
        // rate like being ticked at.
        buffers["timeLow"] = render(notes: [Note(frequency: 196.00, start: 0, duration: 0.4, gain: 0.20)])
    }

    private struct Note {
        let frequency: Double
        let start: Double
        let duration: Double
        let gain: Double
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
            let angular = 2 * Double.pi * note.frequency / sampleRate

            for offset in 0..<noteFrames {
                let frame = firstFrame + offset
                guard frame < Int(frameCount) else { break }
                let progress = Double(offset) / Double(noteFrames)
                let phase = angular * Double(offset)

                // Harmonics decay faster than the fundamental, which is what makes a struck
                // bar sound like wood rather than an organ.
                let fundamental = sin(phase)
                let second = 0.28 * sin(2 * phase) * pow(1 - progress, 2)
                let third = 0.10 * sin(3 * phase) * pow(1 - progress, 3)

                samples[frame] += Float((fundamental + second + third) * envelope(at: progress, frames: noteFrames) * note.gain)
            }
        }

        // Guard against summed notes clipping.
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
    private func envelope(at progress: Double, frames: Int) -> Double {
        let attack = min(0.14, 480.0 / Double(frames))
        if progress < attack {
            return 0.5 * (1 - cos(.pi * progress / attack))
        }
        let releaseProgress = (progress - attack) / (1 - attack)
        return exp(-4.2 * releaseProgress)
    }
}
