import Foundation

/// Character and word counts for the status bar.
nonisolated enum TextStatistics {
    struct Counts: Sendable, Equatable {
        var characters: Int
        var words: Int
    }

    /// Characters are user-perceived characters (grapheme clusters). Words are runs of
    /// non-whitespace separated by whitespace or newlines.
    static func count(_ text: String) -> Counts {
        var characters = 0
        var words = 0
        var inWord = false
        for ch in text {
            characters += 1
            if ch.isWhitespace || ch.isNewline {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        return Counts(characters: characters, words: words)
    }

    static func lineCount(_ text: String) -> Int {
        var lines = 1
        for scalar in text.unicodeScalars where scalar == "\n" { lines += 1 }
        return lines
    }
}
