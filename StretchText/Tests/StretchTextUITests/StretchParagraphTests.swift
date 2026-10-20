import StretchText
import Testing
@testable import StretchTextUI

@Suite("Parágrafos da tela")
struct StretchParagraphTests {
    static let source = """
        Título simples

        O build falha às vezes. O motivo é um cache velho.

        Uma frase só.\r
        \r
        Outro bloco. Com duas frases.
        """

    static func state() -> StretchState {
        StretchState(document: StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source)).document)
    }

    @Test("Texto fixo vira parágrafos; cada trecho vira um parágrafo com a forma curta")
    func closedParagraphs() throws {
        let paragraphs = StretchParagraph.paragraphs(for: Self.state())
        let first = try #require(StretchID("0"))
        let second = try #require(StretchID("1"))
        #expect(paragraphs == [
            StretchParagraph(id: 0, kind: .text, text: "Título simples"),
            StretchParagraph(id: 1, kind: .stretch(first, isOpen: false), text: "O build falha às vezes."),
            StretchParagraph(id: 2, kind: .text, text: "Uma frase só."),
            StretchParagraph(id: 3, kind: .stretch(second, isOpen: false), text: "Outro bloco."),
        ])
    }

    @Test("Abrir mostra o parágrafo inteiro no mesmo lugar")
    func openParagraph() throws {
        var state = Self.state()
        let second = try #require(StretchID("1"))
        #expect(state.toggle(second) == .opened)
        let paragraphs = StretchParagraph.paragraphs(for: state)
        #expect(paragraphs[3] == StretchParagraph(id: 3, kind: .stretch(second, isOpen: true), text: "Outro bloco. Com duas frases."))
        #expect(paragraphs.count == 4)
    }

    @Test("Blocos: linhas em branco separam, quebras simples ficam, CRLF conta como quebra")
    func blocks() {
        #expect(StretchParagraph.blocks(of: "") == [])
        #expect(StretchParagraph.blocks(of: "\n\n  \n") == [])
        #expect(StretchParagraph.blocks(of: "a\nb\n\nc") == ["a\nb", "c"])
        #expect(StretchParagraph.blocks(of: "a\r\n\r\nb") == ["a", "b"])
        #expect(StretchParagraph.blocks(of: "\n\na\n\n") == ["a"])
    }

    @Test("Documento sem trechos vira só texto")
    func noStretches() {
        let state = StretchState(document: StretchDocument(nodes: [.text("Um.\n\nDois.")]))
        #expect(StretchParagraph.paragraphs(for: state).map(\.kind) == [.text, .text])
    }

    @Test("Trecho aninhado aparece dentro do pai, no estado em que está")
    func nestedStretchStaysInsideParent() throws {
        let document = try StretchParser.parse("{{A.|A. {{B.|B e C.}}}}")
        var state = StretchState(document: document)
        let outer = try #require(StretchID("0"))
        let inner = try #require(StretchID("0.0"))
        _ = state.toggle(outer)
        #expect(StretchParagraph.paragraphs(for: state).map(\.text) == ["A. B."])
        _ = state.toggle(inner)
        #expect(StretchParagraph.paragraphs(for: state).map(\.text) == ["A. B e C."])
    }
}
