import Testing
@testable import Plainfile

struct TextStatisticsTests {
    @Test func countsWordsAndCharacters() {
        #expect(TextStatistics.count("") == .init(characters: 0, words: 0))
        #expect(TextStatistics.count("hello") == .init(characters: 5, words: 1))
        #expect(TextStatistics.count("  hello   world \n\n again\t!") == .init(characters: 26, words: 4))
        #expect(TextStatistics.count("héllo wörld 👋") == .init(characters: 13, words: 3))
    }

    @Test func countsLines() {
        #expect(TextStatistics.lineCount("") == 1)
        #expect(TextStatistics.lineCount("a\nb") == 2)
        #expect(TextStatistics.lineCount("a\nb\n") == 3)
    }
}
