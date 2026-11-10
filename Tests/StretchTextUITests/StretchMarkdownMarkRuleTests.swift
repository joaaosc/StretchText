import Foundation
import StretchText
import SwiftUI
import Testing

@testable import StretchTextUI

@Suite("Limites do == como marca-texto na leitura em Markdown")
@MainActor
struct StretchMarkdownMarkRuleTests {
    static func shown(_ text: String, mark: Color?) -> AttributedString {
        MarkdownInline.attributed(text, style: StretchMarkdownHighlightTests.style(mark: mark), highlights: [])
    }

    @Test("Comparação (a==b e c==d) fica literal, sem fundo, como na 1.0")
    func comparisonIsNotMarked() {
        for sample in ["se a==b e c==d", "x==1 e y==2", "a ==b==c"] {
            let text = Self.shown(sample, mark: StretchMarkdownHighlightTests.mark)
            #expect(text == StretchMarkdownHighlightTests.legacy(sample), "\(sample)")
            #expect(!StretchMarkdownHighlightTests.hasBackground(text), "\(sample)")
        }
    }

    @Test("Abertura depois de espaço ou pontuação e fechamento antes de espaço ou pontuação marcam")
    func boundariesMark() {
        let cases: [(source: String, shown: String, painted: [String])] = [
            ("isto ==é marca== aqui", "isto é marca aqui", ["é marca"]),
            ("(==marca==)", "(marca)", ["marca"]),
            ("==marca==.", "marca.", ["marca"]),
            ("==marca==", "marca", ["marca"]),
            ("==a== ==b==", "a b", ["a", "b"]),
            ("se a==b então ==marca== fim", "se a==b então marca fim", ["marca"]),
        ]
        for (source, shown, painted) in cases {
            let text = Self.shown(source, mark: StretchMarkdownHighlightTests.mark)
            #expect(String(text.characters) == shown, "\(source)")
            #expect(StretchMarkdownHighlightTests.painted(text, StretchMarkdownHighlightTests.mark) == painted, "\(source)")
        }
    }

    @Test("Tela, texto do bloco e busca falam do mesmo texto")
    func screenAndSearchAgree() {
        for source in ["se a==b e c==d", "isto ==é marca== aqui", "(==marca==)", "==a== ==b==", "a ==b==c", "x == y"] {
            let block = ReadingBlock(id: 0, kind: .paragraph, text: source)
            let text = Self.shown(source, mark: StretchMarkdownHighlightTests.mark)
            #expect(block.plainText == String(text.characters), "\(source)")
            let matches = ReadingSearch.matches(of: "a", in: [block])
            let characters = Array(block.plainText)
            for match in matches {
                #expect(String(characters[match.range]).lowercased() == "a", "\(source)")
            }
        }
    }
}
