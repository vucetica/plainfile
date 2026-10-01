import Testing
import Foundation
@testable import Plainfile

struct LineScannerTests {

    struct Tok: Equatable {
        let text: String
        let kind: TokenKind
        init(_ text: String, _ kind: TokenKind) { self.text = text; self.kind = kind }
        static func == (lhs: Tok, rhs: (String, TokenKind)) -> Bool { lhs.text == rhs.0 && lhs.kind == rhs.1 }
    }

    private func kinds(_ line: String, _ language: Language, state: LineState = .initial) -> ([Tok], LineState) {
        let chars = Array(line.utf16)
        let (tokens, end) = LineScanner.scan(chars, state: state, language: language)
        let ns = line as NSString
        return (tokens.map { Tok(ns.substring(with: $0.range), $0.kind) }, end)
    }

    @Test func csharpBasics() {
        let (tokens, _) = kinds("public static async Task<int> Main(string[] args) // entry", LanguageRegistry.csharp)
        #expect(tokens.contains { $0 == ("public", .keyword) })
        #expect(tokens.contains { $0 == ("Task", .type) })
        #expect(tokens.contains { $0 == ("Main", .function) })
        #expect(tokens.contains { $0 == ("// entry", .comment) })
    }

    @Test func csharpVerbatimStringSpansLines() {
        let (t1, state) = kinds("var s = @\"C:\\path", LanguageRegistry.csharp)
        #expect(t1.contains { $0.kind == .string })
        #expect(state.mode != 0)
        let (t2, state2) = kinds("more\";", LanguageRegistry.csharp, state: state)
        #expect(t2.first?.kind == .string)
        #expect(state2 == .initial)
    }

    @Test func csharpInterpolatedAndPreprocessor() {
        let (tokens, _) = kinds("#region Foo", LanguageRegistry.csharp)
        #expect(tokens.first == Tok("#region", .preprocessor))
        let (t2, _) = kinds("Console.WriteLine($\"Hello {name}\");", LanguageRegistry.csharp)
        #expect(t2.contains { $0 == ("$\"Hello {name}\"", .string) })
    }

    @Test func swiftNestedBlockComments() {
        let lang = LanguageRegistry.swift
        let (_, s1) = kinds("/* outer /* inner */ still", lang)
        #expect(s1.mode == 1)
        let (t2, s2) = kinds("done */ let x = 1", lang, state: s1)
        #expect(t2.first?.kind == .comment)
        #expect(t2.contains { $0 == ("let", .keyword) })
        #expect(s2 == .initial)
    }

    @Test func pythonTripleQuotedStrings() {
        let lang = LanguageRegistry.python
        let (_, s1) = kinds("doc = \"\"\"start", lang)
        #expect(s1.mode == 2)
        let (t2, s2) = kinds("end\"\"\" # comment", lang, state: s1)
        #expect(t2.first == Tok("end\"\"\"", .string))
        #expect(t2.last == Tok("# comment", .comment))
        #expect(s2 == .initial)
    }

    @Test func rustCharLiteralVsLifetime() {
        let (tokens, _) = kinds("fn f<'a>(c: char) -> &'a str { let x = 'z'; }", LanguageRegistry.rust)
        let strings = tokens.filter { $0.kind == .string }.map(\.text)
        #expect(strings == ["'z'"])
    }

    @Test func shellVariablesAndComments() {
        let (tokens, _) = kinds("echo \"$HOME/${DIR}\" # done", LanguageRegistry.shell)
        #expect(tokens.contains { $0 == ("echo", .type) })
        #expect(tokens.contains { $0.kind == .string })
        #expect(tokens.last == Tok("# done", .comment))
    }

    @Test func jsonKeysAndValues() {
        let (tokens, _) = kinds("{\"name\": \"x\", \"n\": 1.5, \"ok\": true}", LanguageRegistry.json)
        #expect(tokens.contains { $0 == ("\"name\"", .key) })
        #expect(tokens.contains { $0 == ("\"x\"", .string) })
        #expect(tokens.contains { $0 == ("1.5", .number) })
        #expect(tokens.contains { $0 == ("true", .literal) })
    }

    @Test func yamlKeysAndBlockScalars() {
        let lang = LanguageRegistry.yaml
        let (t1, _) = kinds("name: value # c", lang)
        #expect(t1.first == Tok("name", .key))
        #expect(t1.last == Tok("# c", .comment))
        let (_, s2) = kinds("script: |", lang)
        #expect(s2.mode == 9)
        let (t3, s3) = kinds("  echo hi", lang, state: s2)
        #expect(t3.first?.kind == .string)
        #expect(s3.mode == 9)
        let (t4, s4) = kinds("next: 1", lang, state: s3)
        #expect(t4.first == Tok("next", .key))
        #expect(s4 == .initial)
    }

    @Test func htmlTagsAndAttributes() {
        let (tokens, _) = kinds("<a href=\"x\" class=\"y\">hi</a>", LanguageRegistry.html)
        #expect(tokens.contains { $0 == ("<a", .tag) })
        #expect(tokens.contains { $0 == ("href", .attributeName) })
        #expect(tokens.contains { $0 == ("\"x\"", .string) })
        #expect(tokens.contains { $0 == ("</a", .tag) })
    }

    @Test func cssPropertiesAndSelectors() {
        let lang = LanguageRegistry.css
        let (t1, s1) = kinds(".card:hover {", lang)
        #expect(t1.contains { $0 == (".card", .type) })
        #expect(s1.mode == 8)
        let (t2, _) = kinds("  color: #ff0000; width: 10px;", lang, state: s1)
        #expect(t2.contains { $0 == ("color", .key) })
        #expect(t2.contains { $0 == ("#ff0000", .number) })
        #expect(t2.contains { $0 == ("10px", .number) })
    }

    @Test func markdownConstructs() {
        let lang = LanguageRegistry.markdown
        #expect(kinds("## Title", lang).0.first == Tok("## Title", .heading))
        let (t, _) = kinds("- item with **bold** and `code` and [l](u)", lang)
        #expect(t.contains { $0 == ("-", .listMarker) })
        #expect(t.contains { $0 == ("**bold**", .strong) })
        #expect(t.contains { $0 == ("`code`", .codeSpan) })
        #expect(t.contains { $0 == ("[l]", .link) })
        let (_, fence) = kinds("```swift", lang)
        #expect(fence.mode == 3)
        let (inner, s2) = kinds("let x = 1", lang, state: fence)
        #expect(inner.first?.kind == .codeSpan)
        #expect(s2.mode == 3)
        let (_, s3) = kinds("```", lang, state: s2)
        #expect(s3 == .initial)
    }

    @Test func languageDetection() {
        #expect(LanguageRegistry.language(forFileName: "Program.cs")?.id == "csharp")
        #expect(LanguageRegistry.language(forFileName: "Makefile")?.id == "makefile")
        #expect(LanguageRegistry.language(forFileName: "data.CSV")?.id == "csv")
        #expect(LanguageRegistry.language(forFileName: "README.md")?.id == "markdown")
        #expect(LanguageRegistry.language(forShebang: "#!/usr/bin/env python3")?.id == "python")
        #expect(LanguageRegistry.language(forFileName: "notes") == nil)
    }
}
