import Foundation
import Testing

@testable import StretchText

@Suite("Texto exibido do bloco")
struct ReadingPlainTextTests {
    static func plain(_ text: String, kind: ReadingBlock.Kind = .paragraph) -> String {
        ReadingBlock(id: 0, kind: kind, text: text).plainText
    }

    @Test("Negrito, itálico, código e link perdem a marcação")
    func inlineMarkup() {
        #expect(Self.plain("um **dois** _três_ `quatro` e [cinco](https://exemplo.com/seis)") == "um dois três quatro e cinco")
    }

    @Test("Texto sem marcação fica igual, inclusive quebras de linha")
    func plainStaysPlain() {
        #expect(Self.plain("a\nb  c, 3,14 e C:\\pasta.") == "a\nb  c, 3,14 e C:\\pasta.")
        #expect(Self.plain("") == "")
    }

    @Test("O == que forma par sai; o texto de dentro fica")
    func markedText() {
        #expect(Self.plain("veja ==isto== agora") == "veja isto agora")
        #expect(Self.plain("==um== e ==dois==") == "um e dois")
        #expect(Self.plain("==**forte** e _suave_==") == "forte e suave")
        #expect(Self.plain("==[link](https://exemplo.com)==") == "link")
    }

    @Test("O == dentro de código em linha fica literal")
    func markInsideInlineCode() {
        #expect(Self.plain("use `a==b==c` aqui") == "use a==b==c aqui")
        #expect(Self.plain("==fora `a==b` dentro== fim") == "fora a==b dentro fim")
        // Abertura no código, fechamento fora: nenhum dos dois forma par.
        #expect(Self.plain("`==a` e b==") == "==a e b==")
    }

    @Test("O == sem par, com espaço por dentro ou em outra quantidade fica literal")
    func unpairedStaysLiteral() {
        #expect(Self.plain("só ==abre") == "só ==abre")
        #expect(Self.plain("só fecha==") == "só fecha==")
        #expect(Self.plain("x == y e z == w") == "x == y e z == w")
        #expect(Self.plain("a === b e ==== c") == "a === b e ==== c")
        #expect(Self.plain("== espaço ==") == "== espaço ==")
        #expect(Self.plain("====") == "====")
    }

    @Test("O == não atravessa parágrafo, mas atravessa uma quebra de linha simples")
    func markAndParagraphs() {
        #expect(Self.plain("==abre\n\nfecha==", kind: .blockQuote) == "==abre\n\nfecha==")
        #expect(Self.plain("==abre\n  \nfecha==", kind: .blockQuote) == "==abre\n  \nfecha==")
        #expect(Self.plain("==abre\nfecha==", kind: .blockQuote) == "abre\nfecha")
    }

    @Test("Em cada tipo de bloco: título, item e citação leem o texto; código e tabela, não")
    func kinds() {
        #expect(Self.plain("**Título** ==marcado==", kind: .heading(level: 2)) == "Título marcado")
        #expect(Self.plain("fazer ==isto==", kind: .listItem(marker: .task(isDone: false), depth: 0)) == "fazer isto")
        #expect(Self.plain("fazer ==isto==", kind: .listItem(marker: .bullet, depth: 1)) == "fazer isto")
        #expect(Self.plain("citado ==aqui==", kind: .blockQuote) == "citado aqui")
        #expect(Self.plain("let a = **b** ==c==", kind: .codeBlock(language: "swift")) == "let a = **b** ==c==")
        #expect(Self.plain("| ==a== | **b** |", kind: .table) == "| ==a== | **b** |")
        #expect(Self.plain("", kind: .thematicBreak) == "")
        #expect(
            Self.plain("Planta da **cozinha**", kind: .image(MarkdownImage(alt: "Planta da **cozinha**", source: "p.png")))
                == "Planta da **cozinha**")
    }

    @Test("Vindo da segmentação: o trecho dobrado conta o texto que está à mostra")
    func foldedStretch() throws {
        let source = "A **primeira** frase. A ==segunda== frase.\n\n## Título com `código`\n\n```\nx ==y==\n```"
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source))
        var state = StretchState(document: result.document)
        let closed = ReadingBlock.blocks(for: result, state: state).map(\.plainText)
        #expect(closed == ["A primeira frase.", "Título com código", "x ==y=="])

        state.toggle(try #require(StretchID("0")))
        let open = ReadingBlock.blocks(for: result, state: state).map(\.plainText)
        #expect(open == ["A primeira frase. A segunda frase.", "Título com código", "x ==y=="])
    }

    @Test("A abertura do == pede começo, espaço ou pontuação antes; o fechamento, fim, espaço ou pontuação depois")
    func markNeedsBoundaries() {
        // Comparação (`a==b`): o `==` colado em letra ou dígito não é limite de marca.
        #expect(Self.plain("se a==b e c==d") == "se a==b e c==d")
        #expect(Self.plain("a==b e c==d") == "a==b e c==d")
        #expect(Self.plain("x==1 e y==2") == "x==1 e y==2")
        #expect(Self.plain("a ==b==c") == "a ==b==c")
        #expect(Self.plain("a==b ==c==") == "a==b c")
        #expect(Self.plain("se a==b então ==marca== fim") == "se a==b então marca fim")
        // Os limites que valem.
        #expect(Self.plain("isto ==é marca== aqui") == "isto é marca aqui")
        #expect(Self.plain("(==marca==)") == "(marca)")
        #expect(Self.plain("==marca==.") == "marca.")
        #expect(Self.plain("==marca==") == "marca")
        #expect(Self.plain("==1==") == "1")
        #expect(Self.plain("==a== ==b==") == "a b")
        #expect(Self.plain("==a==, ==b==") == "a, b")
        #expect(Self.plain("==abre\nfecha==") == "abre\nfecha")
    }

    @Test("Os marcadores do bloco e do texto concordam: remover os == pareados dá o mesmo texto")
    func markedPositions() {
        let marked = ReadingInline.marked("a ==b== c ==d **e**== f")
        #expect(String(marked.text.characters) == "a b c d e f")
        #expect(marked.marks == [2..<3, 6..<9])
        #expect(marked.delimiters == [2, 3, 6, 9])
    }
}
