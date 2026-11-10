import Foundation
import Testing

@testable import StretchText

@Suite("Busca no texto exibido")
struct ReadingSearchTests {
    static func paragraph(_ id: Int, _ text: String) -> ReadingBlock {
        ReadingBlock(id: id, kind: .paragraph, text: text)
    }

    /// Os trechos achados, como texto, lidos de volta no texto exibido do bloco.
    static func found(_ matches: [ReadingMatch], in blocks: [ReadingBlock]) -> [String] {
        matches.map { match in
            let plain = Array(blocks.first { $0.id == match.block }!.plainText)
            return String(plain[match.range])
        }
    }

    @Test("Ignora maiúsculas e acentos, nos dois sentidos")
    func caseAndAccents() {
        let blocks = [Self.paragraph(0, "Um Café, um CAFÉ e um cafe.")]
        let matches = ReadingSearch.matches(of: "cafe", in: blocks)
        #expect(matches.map(\.range) == [3..<7, 12..<16, 22..<26])
        #expect(Self.found(matches, in: blocks) == ["Café", "CAFÉ", "cafe"])
        #expect(ReadingSearch.matches(of: "CAFÉ", in: blocks).count == 3)
    }

    @Test("Ignora a largura dos caracteres")
    func width() {
        let blocks = [Self.paragraph(0, "ＡＢＣ abc")]
        #expect(ReadingSearch.matches(of: "abc", in: blocks).map(\.range) == [0..<3, 4..<7])
    }

    @Test("Letra com acento decomposto conta como um caractere")
    func decomposedAccent() {
        let blocks = [Self.paragraph(0, "cafe\u{301}!")]
        #expect(ReadingSearch.matches(of: "cafe", in: blocks).map(\.range) == [0..<4])
        #expect(ReadingSearch.matches(of: "é!", in: blocks).map(\.range) == [3..<5])
    }

    @Test("Várias ocorrências no bloco não se sobrepõem")
    func severalInOneBlock() {
        let blocks = [Self.paragraph(4, "aaaa a")]
        #expect(
            ReadingSearch.matches(of: "aa", in: blocks) == [
                ReadingMatch(block: 4, range: 0..<2),
                ReadingMatch(block: 4, range: 2..<4),
            ])
    }

    @Test("Vários blocos: cada ocorrência traz o id do bloco, na ordem do texto")
    func severalBlocks() {
        let blocks = [
            Self.paragraph(0, "sem nada"),
            Self.paragraph(2, "casa e Casa"),
            ReadingBlock(id: 3, kind: .heading(level: 1), text: "A **CASA**"),
            ReadingBlock(id: 5, kind: .listItem(marker: .bullet, depth: 0), text: "casa"),
        ]
        let matches = ReadingSearch.matches(of: "casa", in: blocks)
        #expect(
            matches == [
                ReadingMatch(block: 2, range: 0..<4),
                ReadingMatch(block: 2, range: 7..<11),
                ReadingMatch(block: 3, range: 2..<6),
                ReadingMatch(block: 5, range: 0..<4),
            ])
    }

    @Test("As posições contam o texto exibido, sem a marcação nem os ==")
    func positionsInDisplayedText() {
        let blocks = [Self.paragraph(0, "um **forte** ==acordo== firme")]
        let matches = ReadingSearch.matches(of: "acordo firme", in: blocks)
        #expect(matches.map(\.range) == [9..<21])
        #expect(Self.found(matches, in: blocks) == ["acordo firme"])
    }

    @Test("O que só existe na marcação não é achado")
    func markupOnlyIsNotFound() {
        let blocks = [
            Self.paragraph(0, "veja [o site](https://exemplo.com/pagina) e **isto** com ==marca=="),
            ReadingBlock(id: 1, kind: .image(MarkdownImage(alt: "pagina", source: "pagina.png")), text: "pagina"),
        ]
        #expect(ReadingSearch.matches(of: "exemplo", in: blocks).isEmpty)
        #expect(ReadingSearch.matches(of: "https", in: blocks).isEmpty)
        #expect(ReadingSearch.matches(of: "**", in: blocks).isEmpty)
        #expect(ReadingSearch.matches(of: "==", in: blocks).isEmpty)
        // O texto do link e o texto alternativo da imagem: só o do link está na tela do pacote.
        #expect(ReadingSearch.matches(of: "o site", in: blocks).count == 1)
        #expect(ReadingSearch.matches(of: "pagina", in: blocks).isEmpty)
    }

    @Test("Código e tabela são literais: a marcação deles é achada")
    func codeIsLiteral() {
        let blocks = [ReadingBlock(id: 0, kind: .codeBlock(language: nil), text: "let a = **b** ==c==")]
        #expect(ReadingSearch.matches(of: "==c", in: blocks).map(\.range) == [14..<17])
    }

    @Test("Respeita o teto, dentro do bloco e entre blocos")
    func limit() {
        let blocks = [Self.paragraph(0, "a a a"), Self.paragraph(1, "a a")]
        #expect(ReadingSearch.matches(of: "a", in: blocks).count == 5)
        #expect(ReadingSearch.matches(of: "a", in: blocks, limit: 4).map(\.block) == [0, 0, 0, 1])
        #expect(ReadingSearch.matches(of: "a", in: blocks, limit: 2).count == 2)
        #expect(ReadingSearch.matches(of: "a", in: blocks, limit: 0).isEmpty)
    }

    @Test("Consulta vazia ou só com espaços não acha nada; as bordas em branco não contam")
    func emptyQuery() {
        let blocks = [Self.paragraph(0, "um dois  três")]
        #expect(ReadingSearch.matches(of: "", in: blocks).isEmpty)
        #expect(ReadingSearch.matches(of: "   \n\t", in: blocks).isEmpty)
        #expect(ReadingSearch.matches(of: " dois ", in: blocks).map(\.range) == [3..<7])
        #expect(ReadingSearch.matches(of: "dois", in: []).isEmpty)
    }

    @Test("Texto grande: o teto vale e as posições continuam certas até o fim")
    func largeText() {
        let text = String(repeating: "palavra outra ", count: 20_000) + "fim"
        let blocks = [Self.paragraph(0, text)]
        #expect(ReadingSearch.matches(of: "palavra", in: blocks).count == 500)
        let all = ReadingSearch.matches(of: "palavra", in: blocks, limit: 100_000)
        #expect(all.count == 20_000)
        #expect(all.last?.range == (19_999 * 14)..<(19_999 * 14 + 7))
        #expect(ReadingSearch.matches(of: "fim", in: blocks).map(\.range) == [280_000..<280_003])
    }
}
