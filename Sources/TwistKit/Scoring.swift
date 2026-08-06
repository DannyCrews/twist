/// What a word is worth, and what finishing a round is worth on top.
public enum Scoring {
    /// Ten points per letter squared: 90, 160, 250, 360, 490 for three through seven letters.
    ///
    /// This reproduces the curve of the original Text Twist. Its sequel flattened the scale to
    /// 1500/2000/2500/3000/3500, which makes a seven-letter word worth barely twice a
    /// three-letter one and removes most of the reason to hunt for the long ones.
    public static func points(forWordOfLength length: Int) -> Int {
        guard length >= Round.minimumWordLength else { return 0 }
        return 10 * length * length
    }

    public static func points(for word: some StringProtocol) -> Int {
        points(forWordOfLength: word.count)
    }

    /// Multiplier applied to the round's word score when every common word has been found.
    ///
    /// The target counts only common words, so this stays reachable — in the original the
    /// bonus was gated on a word list that included entries almost nobody knows.
    public static let completionMultiplier = 2

    public static func bonus(forWordScore score: Int, completed: Bool) -> Int {
        completed ? score * (completionMultiplier - 1) : 0
    }
}
