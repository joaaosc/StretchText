import Foundation
import Testing
@testable import StretchText

/// Bloco esperado: tipo e texto literal.
struct Piece: Equatable, Sendable, CustomStringConvertible {
    let kind: Segment.Kind
    let text: String

    var description: String { "\(kind)(\(text.debugDescription))" }

    static func paragraph(_ text: String) -> Piece { Piece(kind: .paragraph, text: text) }
    static func heading(_ text: String) -> Piece { Piece(kind: .heading, text: text) }
    static func item(_ text: String) -> Piece { Piece(kind: .listItem, text: text) }
    static func code(_ text: String) -> Piece { Piece(kind: .codeBlock, text: text) }
    static func table(_ text: String) -> Piece { Piece(kind: .table, text: text) }
    static func quote(_ text: String) -> Piece { Piece(kind: .blockQuote, text: text) }
    static func rule(_ text: String) -> Piece { Piece(kind: .thematicBreak, text: text) }
    static func blank(_ text: String) -> Piece { Piece(kind: .blank, text: text) }
}

func pieces(of source: String) -> [Piece] {
    TextSegmenter.segment(source).segments.map { Piece(kind: $0.kind, text: $0.text) }
}

/// Entradas usadas para conferir a partição exata e, no outro arquivo, a
/// montagem: vazia, só espaços, CRLF, sem quebra final, emoji, acentos e
/// todos os tipos de bloco.
enum SegmentationFixtures {
    static let partitionInputs: [String] = [
        "",
        "   ",
        "\n\n",
        " \t \n",
        "Uma única frase",
        "Sem quebra final. Duas frases.",
        "Com quebra final. Duas frases.\n",
        "Linha um.\r\nLinha dois. Mais uma.\r\n\r\nOutro parágrafo. Fim.\r\n",
        "Quebra antiga.\rOutra linha. Fim.\r\r",
        "  \n\t\n# Título\n\n  Parágrafo com recuo. Segundo.\n   \n",
        "Café com açúcar. Pão de queijo! Será que sim?\n\nÁgua é vida… Sempre.",
        "Emoji 😀 aqui. Depois 👩‍👩‍👧‍👦 também. Fim.\n\n日本語の文章です。次の文です。",
        "```swift\nlet x = 1.\n\nlet y = 2\n```\n\nDepois do código. Fim.",
        "```\nsem fechamento\n\n\n",
        "- item um. Frase dois.\n- item dois\n\n  continuação do item. Outra.\n\n1. um\n2. dois\n",
        "> citação. Com duas frases.\n> segunda linha\n\n| a | b |\n|---|---|\n| 1 | 2 |\n",
        "Título setext\n=============\n\nOutro\n---\n\n***\n\n    código indentado\n    mais\n",
        "Parágrafo. Um\n1. item numerado\ndepois. Mais\n\nEm 2024.\nDepois disso. Fim.",
        "\u{FEFF}Com marca de ordem. Segunda frase.",
        "Com\ttab. Segunda.\t\n\t\n",
        "\n\r\nMisto de quebras. Segunda frase.\r\n\n",
    ]
}

/// Confere as invariantes de qualquer segmentação.
func expectWellFormed(_ segmentation: Segmentation, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
    let source = segmentation.source
    let segments = segmentation.segments
    #expect(segments.map(\.text).joined() == source, "a partição deve reproduzir a origem", sourceLocation: sourceLocation)
    #expect(segments.map(\.id) == Array(segments.indices), "IDs em ordem a partir de 0", sourceLocation: sourceLocation)

    let bytes = Array(source.utf8)
    var cursor = 0
    var previousWasBlank = false
    for segment in segments {
        #expect(segment.utf8Range.lowerBound == cursor, "blocos contíguos", sourceLocation: sourceLocation)
        #expect(!segment.text.isEmpty, "nenhum bloco vazio", sourceLocation: sourceLocation)
        cursor = segment.utf8Range.upperBound
        #expect(
            Array(segment.text.utf8) == Array(bytes[segment.utf8Range]),
            "utf8Range aponta para o texto do bloco",
            sourceLocation: sourceLocation
        )
        if segment.kind == .blank {
            #expect(!previousWasBlank, "nunca dois .blank seguidos", sourceLocation: sourceLocation)
        } else {
            #expect(segment.text.last?.isNewline == false, "bloco não termina em quebra de linha", sourceLocation: sourceLocation)
        }
        previousWasBlank = segment.kind == .blank

        let textBytes = Array(segment.text.utf8)
        if segment.kind != .paragraph {
            #expect(segment.sentences.isEmpty, "só parágrafo tem frases", sourceLocation: sourceLocation)
        }
        for (index, sentence) in segment.sentences.enumerated() {
            #expect(sentence.id == SentenceID(segment: segment.id, index: index), sourceLocation: sourceLocation)
            #expect(
                Array(sentence.text.utf8) == Array(textBytes[sentence.utf8Range]),
                "utf8Range da frase aponta para o texto dela",
                sourceLocation: sourceLocation
            )
        }
    }
    #expect(cursor == bytes.count, "os blocos cobrem toda a origem", sourceLocation: sourceLocation)
}

@Suite("Segmentação em blocos")
struct TextSegmenterTests {
    struct Example: Sendable, CustomTestStringConvertible {
        let name: String
        let source: String
        let expected: [Piece]

        init(_ name: String, _ source: String, _ expected: [Piece]) {
            self.name = name
            self.source = source
            self.expected = expected
        }

        var testDescription: String { name }
    }

    @Test("A versão do segmentador é 1")
    func version() {
        #expect(TextSegmenter.version == 1)
    }

    // MARK: - Partição

    @Test("Partição exata, IDs e utf8Range corretos", arguments: SegmentationFixtures.partitionInputs)
    func exactPartition(_ source: String) {
        let segmentation = TextSegmenter.segment(source)
        #expect(segmentation.source == source)
        expectWellFormed(segmentation)
    }

    @Test("Texto vazio não gera blocos")
    func emptySource() {
        #expect(TextSegmenter.segment("").segments.isEmpty)
    }

    @Test("Só espaços e quebras viram um único .blank")
    func onlyWhitespace() {
        #expect(pieces(of: "   ") == [.blank("   ")])
        #expect(pieces(of: " \t\n\n  \n") == [.blank(" \t\n\n  \n")])
    }

    @Test("utf8Range conta bytes UTF-8, não caracteres")
    func utf8RangesAreBytes() {
        let segmentation = TextSegmenter.segment("é 😀\n\nÁgua")
        let ranges = segmentation.segments.map(\.utf8Range)
        // "é 😀" = 2 + 1 + 4 bytes; "\n\n" = 2; "Água" = 5.
        #expect(ranges == [0..<7, 7..<9, 9..<14])
        #expect(segmentation.segments.map(\.kind) == [.paragraph, .blank, .paragraph])
    }

    // MARK: - Cada tipo de bloco

    static let paragraphAndBlankExamples: [Example] = [
        Example("parágrafo de uma linha", "Olá, mundo.", [.paragraph("Olá, mundo.")]),
        Example("linhas seguidas formam um parágrafo", "Um.\nDois.", [.paragraph("Um.\nDois.")]),
        Example("linha em branco separa parágrafos", "A\n\nB", [.paragraph("A"), .blank("\n\n"), .paragraph("B")]),
        Example("quebra final fica no .blank", "A\n", [.paragraph("A"), .blank("\n")]),
        Example(
            "linhas só com espaços e tabs entram no .blank",
            "A\n \t \n\nB",
            [.paragraph("A"), .blank("\n \t \n\n"), .paragraph("B")]
        ),
        Example(
            "branco no início, recuo e espaço no fim",
            "\n\n  \nTexto  \n \t \n\nFim\n  ",
            [.blank("\n\n  \n"), .paragraph("Texto  "), .blank("\n \t \n\n"), .paragraph("Fim"), .blank("\n  ")]
        ),
        Example("recuo de 1 a 3 espaços continua parágrafo", "   Texto", [.paragraph("   Texto")]),
        Example("parágrafo com sinais no meio", "a # b > c | d", [.paragraph("a # b > c | d")]),
    ]

    @Test("Parágrafos e espaços", arguments: paragraphAndBlankExamples)
    func paragraphsAndBlanks(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    static let headingExamples: [Example] = [
        Example("nível 1", "# Título", [.heading("# Título")]),
        Example("nível 6", "###### Título", [.heading("###### Título")]),
        Example("sete cerquilhas é parágrafo", "####### Título", [.paragraph("####### Título")]),
        Example("sem espaço é parágrafo", "#hashtag", [.paragraph("#hashtag")]),
        Example("cerquilha sozinha", "#", [.heading("#")]),
        Example("tab depois da cerquilha", "#\tTítulo", [.heading("#\tTítulo")]),
        Example("até três espaços antes", "   # Título", [.heading("   # Título")]),
        Example("quatro espaços é código", "    # Título", [.code("    # Título")]),
        Example("fechamento opcional", "## Título ##", [.heading("## Título ##")]),
        Example(
            "interrompe parágrafo",
            "Texto\n# Título\nMais texto",
            [.paragraph("Texto"), .blank("\n"), .heading("# Título"), .blank("\n"), .paragraph("Mais texto")]
        ),
    ]

    @Test("Títulos de cerquilha", arguments: headingExamples)
    func atxHeadings(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    static let setextExamples: [Example] = [
        Example("sublinhado com =", "Título\n===", [.heading("Título\n===")]),
        Example("sublinhado com -", "Título\n---", [.heading("Título\n---")]),
        Example(
            "parágrafo de várias linhas inteiro vira título",
            "Linha um\nlinha dois\n---",
            [.heading("Linha um\nlinha dois\n---")]
        ),
        Example("um único - basta", "Texto\n-", [.heading("Texto\n-")]),
        Example("espaços no fim do sublinhado", "Texto\n=  ", [.heading("Texto\n=  ")]),
        Example("até três espaços antes do sublinhado", "Texto\n   ===", [.heading("Texto\n   ===")]),
        Example("= misturado com texto não é sublinhado", "Texto\n=a", [.paragraph("Texto\n=a")]),
        Example(
            "--- depois de linha em branco é separador",
            "Texto\n\n---",
            [.paragraph("Texto"), .blank("\n\n"), .rule("---")]
        ),
        Example(
            "--- logo depois do parágrafo é título",
            "Texto\n---\nDepois",
            [.heading("Texto\n---"), .blank("\n"), .paragraph("Depois")]
        ),
        Example(
            "=== sem parágrafo aberto é parágrafo",
            "===\nTexto",
            [.paragraph("===\nTexto")]
        ),
    ]

    @Test("Títulos com sublinhado (setext)", arguments: setextExamples)
    func setextHeadings(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    @Test("Separadores temáticos", arguments: ["---", "***", "___", "-----", "- - -", " * * * ", "_ _ _ _", "   ---"])
    func thematicBreaks(_ source: String) {
        #expect(pieces(of: source) == [.rule(source)])
    }

    @Test("Dois caracteres não formam separador", arguments: ["--", "**", "__", "-*-", "- -"])
    func notThematicBreaks(_ source: String) {
        #expect(pieces(of: source).map(\.kind) != [.thematicBreak])
    }

    @Test("*** e ___ interrompem parágrafo; - - - também")
    func thematicBreaksInterruptParagraph() {
        #expect(pieces(of: "Texto\n***") == [.paragraph("Texto"), .blank("\n"), .rule("***")])
        #expect(pieces(of: "Texto\n___") == [.paragraph("Texto"), .blank("\n"), .rule("___")])
        #expect(pieces(of: "Texto\n- - -") == [.paragraph("Texto"), .blank("\n"), .rule("- - -")])
    }

    static let tableExamples: [Example] = [
        Example("linhas com barra no início", "| a | b |\n| 1 | 2 |", [.table("| a | b |\n| 1 | 2 |")]),
        Example(
            "linha sem barra encerra a tabela",
            "| a |\ntexto sem barra",
            [.table("| a |"), .blank("\n"), .paragraph("texto sem barra")]
        ),
        Example(
            "cabeçalho sem barra inicial com delimitador",
            "a | b\n--|--\n1 | 2\n\nDepois",
            [.table("a | b\n--|--\n1 | 2"), .blank("\n\n"), .paragraph("Depois")]
        ),
        Example("delimitador com dois-pontos", "Nome\n:---:|---", [.table("Nome\n:---:|---")]),
        Example("cabeçalho de uma coluna", "Texto\n|---|\n", [.table("Texto\n|---|"), .blank("\n")]),
        Example(
            "linha com barra interrompe parágrafo",
            "Texto\n| a |",
            [.paragraph("Texto"), .blank("\n"), .table("| a |")]
        ),
        Example(
            "linha em branco separa tabelas",
            "| a |\n\n| b |",
            [.table("| a |"), .blank("\n\n"), .table("| b |")]
        ),
        Example("até três espaços antes da barra", "  | a |", [.table("  | a |")]),
        Example("barra no meio da linha não abre tabela", "a | b", [.paragraph("a | b")]),
        Example("delimitador sem barra não é tabela", "Texto\n:--", [.paragraph("Texto\n:--")]),
    ]

    @Test("Tabelas", arguments: tableExamples)
    func tables(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    static let listExamples: [Example] = [
        Example(
            "um bloco por item",
            "- a\n- b\n- c",
            [.item("- a"), .blank("\n"), .item("- b"), .blank("\n"), .item("- c")]
        ),
        Example("marcadores * e +", "* a\n+ b", [.item("* a"), .blank("\n"), .item("+ b")]),
        Example(
            "numerados com . e )",
            "1. um\n2. dois\n10) dez",
            [.item("1. um"), .blank("\n"), .item("2. dois"), .blank("\n"), .item("10) dez")]
        ),
        Example(
            "linhas seguintes continuam o item",
            "- item\ncontinua aqui\n  e aqui",
            [.item("- item\ncontinua aqui\n  e aqui")]
        ),
        Example("sem espaço depois do marcador é parágrafo", "-sem espaço", [.paragraph("-sem espaço")]),
        Example("número sem espaço é parágrafo", "1.sem espaço", [.paragraph("1.sem espaço")]),
        Example("dez dígitos não é marcador", "1234567890. texto", [.paragraph("1234567890. texto")]),
        Example("marcador com tab", "-\ttexto", [.item("-\ttexto")]),
        Example(
            "subitem recuado em até 3 espaços é outro item",
            "- a\n  - b",
            [.item("- a"), .blank("\n"), .item("  - b")]
        ),
        Example(
            "parágrafo de continuação após linha em branco",
            "- a\n\n  continuação",
            [.item("- a"), .blank("\n\n"), .item("  continuação")]
        ),
        Example(
            "continuação com recuo fundo",
            "- a\n\n    continuação funda",
            [.item("- a"), .blank("\n\n"), .item("    continuação funda")]
        ),
        Example(
            "continuação encadeada",
            "- a\n\n  segunda\n\n  terceira",
            [.item("- a"), .blank("\n\n"), .item("  segunda"), .blank("\n\n"), .item("  terceira")]
        ),
        Example(
            "recuo de um espaço não continua o item",
            "- a\n\n continuação",
            [.item("- a"), .blank("\n\n"), .paragraph(" continuação")]
        ),
        Example(
            "texto sem recuo encerra a continuação",
            "- a\n\n  segunda\n\nfora",
            [.item("- a"), .blank("\n\n"), .item("  segunda"), .blank("\n\n"), .paragraph("fora")]
        ),
        Example(
            "recuo fundo sem item antes é código",
            "Texto\n\n    - fundo",
            [.paragraph("Texto"), .blank("\n\n"), .code("    - fundo")]
        ),
        Example(
            "item seguido de item depois de linha em branco",
            "- a\n\n- b",
            [.item("- a"), .blank("\n\n"), .item("- b")]
        ),
        Example(
            "cerca recuada dentro do item abre bloco de código",
            "- a\n  ```\n  x\n  ```",
            [.item("- a"), .blank("\n"), .code("  ```\n  x\n  ```")]
        ),
        Example(
            "item termina em título",
            "- a\n# T",
            [.item("- a"), .blank("\n"), .heading("# T")]
        ),
        Example(
            "item termina em citação",
            "- a\n> q",
            [.item("- a"), .blank("\n"), .quote("> q")]
        ),
        Example(
            "item seguido de separador",
            "- a\n---",
            [.item("- a"), .blank("\n"), .rule("---")]
        ),
        Example(
            "item de lista interrompe parágrafo",
            "Texto\n- item",
            [.paragraph("Texto"), .blank("\n"), .item("- item")]
        ),
    ]

    @Test("Itens de lista", arguments: listExamples)
    func listItems(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    @Test("Item numerado \"1.\" interrompe parágrafo; \"2024.\" e \"2.\" não")
    func numberedItemInterruptsOnlyWhenOne() {
        #expect(pieces(of: "Texto\n1. item") == [.paragraph("Texto"), .blank("\n"), .item("1. item")])
        #expect(pieces(of: "Texto\n1) item") == [.paragraph("Texto"), .blank("\n"), .item("1) item")])
        #expect(pieces(of: "Em\n2024. Depois") == [.paragraph("Em\n2024. Depois")])
        #expect(pieces(of: "Texto\n2. item") == [.paragraph("Texto\n2. item")])
        #expect(pieces(of: "Texto\n10. item") == [.paragraph("Texto\n10. item")])
    }

    static let quoteExamples: [Example] = [
        Example("linhas consecutivas", "> a\n> b\n>c", [.quote("> a\n> b\n>c")]),
        Example(
            "sem > a linha vira parágrafo",
            "> a\ncontinua",
            [.quote("> a"), .blank("\n"), .paragraph("continua")]
        ),
        Example("até três espaços antes", "   > a", [.quote("   > a")]),
        Example("quatro espaços é código", "    > a", [.code("    > a")]),
        Example(
            "linha em branco separa citações",
            "> a\n\n> b",
            [.quote("> a"), .blank("\n\n"), .quote("> b")]
        ),
        Example(
            "interrompe parágrafo",
            "Texto\n> citado",
            [.paragraph("Texto"), .blank("\n"), .quote("> citado")]
        ),
    ]

    @Test("Citações", arguments: quoteExamples)
    func blockQuotes(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    static let fenceExamples: [Example] = [
        Example("cerca de crases", "```\ncódigo\n```", [.code("```\ncódigo\n```")]),
        Example(
            "linha em branco dentro da cerca fica no bloco",
            "```swift\nlet a = 1\n\nlet b = 2\n```\nDepois",
            [.code("```swift\nlet a = 1\n\nlet b = 2\n```"), .blank("\n"), .paragraph("Depois")]
        ),
        Example("cerca de tis", "~~~\nx\n~~~", [.code("~~~\nx\n~~~")]),
        Example(
            "sem fechamento vai até o fim",
            "```\nabre sem fechar\n\nlinha",
            [.code("```\nabre sem fechar\n\nlinha")]
        ),
        Example(
            "sem fechamento não leva as linhas em branco finais",
            "```\nabre\n\n\n",
            [.code("```\nabre"), .blank("\n\n\n")]
        ),
        Example("só a abertura", "```", [.code("```")]),
        Example(
            "fechamento mais curto não fecha",
            "````\n```\ninterno\n```\n````",
            [.code("````\n```\ninterno\n```\n````")]
        ),
        Example(
            "fechamento mais longo fecha",
            "```\nx\n`````\ndepois",
            [.code("```\nx\n`````"), .blank("\n"), .paragraph("depois")]
        ),
        Example(
            "caractere diferente não fecha",
            "```\nx\n~~~\ny\n```",
            [.code("```\nx\n~~~\ny\n```")]
        ),
        Example(
            "texto depois da cerca de fechamento não fecha",
            "```\nx\n``` texto\ny",
            [.code("```\nx\n``` texto\ny")]
        ),
        Example("espaços depois do fechamento", "```\nx\n```   \n", [.code("```\nx\n```   "), .blank("\n")]),
        Example("cerca recuada em até 3 espaços", "   ```\nx\n   ```", [.code("   ```\nx\n   ```")]),
        Example(
            "quatro espaços antes da cerca é código indentado",
            "    ```\nx",
            [.code("    ```"), .blank("\n"), .paragraph("x")]
        ),
        Example(
            "cerca interrompe parágrafo",
            "Texto\n```\ncodigo\n```\nTexto 2",
            [.paragraph("Texto"), .blank("\n"), .code("```\ncodigo\n```"), .blank("\n"), .paragraph("Texto 2")]
        ),
        Example(
            "título dentro da cerca não vira título",
            "```\n# não é título\n---\n```",
            [.code("```\n# não é título\n---\n```")]
        ),
    ]

    @Test("Cercas de código", arguments: fenceExamples)
    func fencedCode(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    static let indentedCodeExamples: [Example] = [
        Example(
            "linhas indentadas consecutivas",
            "    a\n    b\n\n    c",
            [.code("    a\n    b"), .blank("\n\n"), .code("    c")]
        ),
        Example("tab", "\ta\n\tb", [.code("\ta\n\tb")]),
        Example("recuo continua parágrafo aberto", "Texto\n    continua", [.paragraph("Texto\n    continua")]),
        Example(
            "depois de linha em branco abre código",
            "Texto\n\n    código",
            [.paragraph("Texto"), .blank("\n\n"), .code("    código")]
        ),
        Example(
            "linha menos indentada encerra o código",
            "    a\n  b",
            [.code("    a"), .blank("\n"), .paragraph("  b")]
        ),
        Example(
            "logo depois de um título",
            "# T\n    code",
            [.heading("# T"), .blank("\n"), .code("    code")]
        ),
        Example(
            "várias linhas em branco separam blocos de código",
            "    a\n\n\n    b",
            [.code("    a"), .blank("\n\n\n"), .code("    b")]
        ),
        Example("tab depois de espaços", " \tcódigo", [.code(" \tcódigo")]),
    ]

    @Test("Código indentado", arguments: indentedCodeExamples)
    func indentedCode(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
    }

    // MARK: - Quebras de linha

    static let lineBreakExamples: [Example] = [
        Example(
            "CRLF",
            "A. B.\r\n\r\n# T\r\n- x\r\n",
            [.paragraph("A. B."), .blank("\r\n\r\n"), .heading("# T"), .blank("\r\n"), .item("- x"), .blank("\r\n")]
        ),
        Example("CR sozinho", "A\r\rB", [.paragraph("A"), .blank("\r\r"), .paragraph("B")]),
        Example("quebras misturadas no mesmo parágrafo", "A\r\nB\nC\rD", [.paragraph("A\r\nB\nC\rD")]),
        Example(
            "CRLF dentro de cerca",
            "```\r\nx\r\n```\r\ny",
            [.code("```\r\nx\r\n```"), .blank("\r\n"), .paragraph("y")]
        ),
        Example("CR e LF separados são duas linhas", "a\n\rb", [.paragraph("a"), .blank("\n\r"), .paragraph("b")]),
    ]

    @Test("Quebras de linha \\n, \\r\\n e \\r", arguments: lineBreakExamples)
    func lineBreaks(_ example: Example) {
        #expect(pieces(of: example.source) == example.expected)
        expectWellFormed(TextSegmenter.segment(example.source))
    }

    // MARK: - Documentos realistas

    static let portugueseDocument = """
    # Guia de viagem

    Lisboa é a capital de Portugal. Fica à beira do Tejo. O clima é ameno.

    ## O que ver

    - Castelo de São Jorge
    - Torre de Belém. Patrimônio mundial.

    Dr. Silva recomenda o passeio. Ele mora lá desde 2010.

    > "Vale a pena." Disse o guia.

    ```swift
    let preço = 3.50
    ```

    | Dia | Atividade |
    |---|---|
    | 1 | Castelo |

    ---

    Fim. Boa viagem!

    """

    @Test("Documento misto em português")
    func portugueseDocumentSegmentation() {
        let expected: [Piece] = [
            .heading("# Guia de viagem"), .blank("\n\n"),
            .paragraph("Lisboa é a capital de Portugal. Fica à beira do Tejo. O clima é ameno."), .blank("\n\n"),
            .heading("## O que ver"), .blank("\n\n"),
            .item("- Castelo de São Jorge"), .blank("\n"),
            .item("- Torre de Belém. Patrimônio mundial."), .blank("\n\n"),
            .paragraph("Dr. Silva recomenda o passeio. Ele mora lá desde 2010."), .blank("\n\n"),
            .quote("> \"Vale a pena.\" Disse o guia."), .blank("\n\n"),
            .code("```swift\nlet preço = 3.50\n```"), .blank("\n\n"),
            .table("| Dia | Atividade |\n|---|---|\n| 1 | Castelo |"), .blank("\n\n"),
            .rule("---"), .blank("\n\n"),
            .paragraph("Fim. Boa viagem!"), .blank("\n"),
        ]
        let segmentation = TextSegmenter.segment(Self.portugueseDocument)
        #expect(segmentation.segments.map { Piece(kind: $0.kind, text: $0.text) } == expected)
        expectWellFormed(segmentation)

        let counts = segmentation.segments.filter { $0.kind == .paragraph }.map(\.sentences.count)
        #expect(counts == [3, 2, 2])
    }

    static let englishDocument = """
    Release notes
    =============

    Version 2.1 is out. Mr. Smith wrote most of it, e.g. the parser. It is fast!

    1. Install the package.
    2. Run the tests.

        $ swift test

    Note: see fig. 3 for details. The U.S. team agrees.
    > "It works." Really.
    """

    @Test("Documento misto em inglês")
    func englishDocumentSegmentation() {
        let expected: [Piece] = [
            .heading("Release notes\n============="), .blank("\n\n"),
            .paragraph("Version 2.1 is out. Mr. Smith wrote most of it, e.g. the parser. It is fast!"), .blank("\n\n"),
            .item("1. Install the package."), .blank("\n"),
            .item("2. Run the tests."), .blank("\n\n"),
            .item("    $ swift test"), .blank("\n\n"),
            .paragraph("Note: see fig. 3 for details. The U.S. team agrees."), .blank("\n"),
            .quote("> \"It works.\" Really."),
        ]
        let segmentation = TextSegmenter.segment(Self.englishDocument)
        #expect(segmentation.segments.map { Piece(kind: $0.kind, text: $0.text) } == expected)
        expectWellFormed(segmentation)

        let paragraphs = segmentation.segments.filter { $0.kind == .paragraph }
        #expect(paragraphs.map(\.sentences.count) == [3, 2])
        #expect(paragraphs[0].sentences.map(\.text) == ["Version 2.1 is out.", "Mr. Smith wrote most of it, e.g. the parser.", "It is fast!"])
    }

    @Test("Só parágrafos recebem frases, com IDs do bloco")
    func onlyParagraphsHaveSentences() {
        let segmentation = TextSegmenter.segment("# Um. Dois.\n\nTrês. Quatro.\n\n- Cinco. Seis.\n\n> Sete. Oito.\n")
        for segment in segmentation.segments {
            if segment.kind == .paragraph {
                #expect(segment.sentences.map(\.id) == [
                    SentenceID(segment: segment.id, index: 0),
                    SentenceID(segment: segment.id, index: 1),
                ])
            } else {
                #expect(segment.sentences.isEmpty)
            }
        }
        #expect(segmentation.segments.filter { $0.kind == .paragraph }.map(\.id) == [2])
    }

    @Test("Segmentação é determinística")
    func deterministic() {
        for source in SegmentationFixtures.partitionInputs {
            #expect(TextSegmenter.segment(source) == TextSegmenter.segment(source))
        }
    }

    @Test("Cerca, título, citação e separador interrompem a tabela")
    func blocksInterruptTable() {
        let kinds = TextSegmenter.segment("| a |\n```x|y\n\nTexto. Dois.").segments.map(\.kind)
        #expect(kinds == [.table, .blank, .codeBlock])
        let heading = TextSegmenter.segment("| a | b |\n# T | x\n| c |").segments.map(\.kind)
        #expect(heading == [.table, .blank, .heading, .blank, .table])
    }

    @Test("Cerca de crases com crase na linha de abertura é parágrafo")
    func backtickInfoIsNotFence() {
        let kinds = TextSegmenter.segment("```inline``` texto. Mais.\n```\ncódigo\n```").segments.map(\.kind)
        #expect(kinds == [.paragraph, .blank, .codeBlock])
    }

    @Test("Separadores Unicode de linha não quebram linha na segmentação")
    func unicodeLineSeparatorsStayInLine() {
        let kinds = TextSegmenter.segment("Um.\u{2028}# Não é título. Fim.").segments.map(\.kind)
        #expect(kinds == [.paragraph])
    }

    @Test("Segmentação decodificada é conferida")
    func decodingChecksInvariants() throws {
        let segmentation = TextSegmenter.segment("# T\n\nUma frase. Outra frase.")
        let data = try JSONEncoder().encode(segmentation)
        #expect(try JSONDecoder().decode(Segmentation.self, from: data) == segmentation)

        let json = String(decoding: data, as: UTF8.self)
        for tampered in [
            json.replacingOccurrences(of: "\"Outra frase.\"", with: "\"TEXTO INVENTADO\""),
            json.replacingOccurrences(of: "\"source\":\"# T", with: "\"source\":\"# X"),
        ] {
            #expect(tampered != json)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(Segmentation.self, from: Data(tampered.utf8))
            }
        }
    }

    @Test("Muitos blocos são montados em tempo linear", .timeLimit(.minutes(1)))
    func manyBlocksFoldQuickly() {
        let unit = "# Título\n\nUma frase só.\n\n- item\n"
        let source = String(repeating: unit, count: 40_000)
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source))
        #expect(result.document.nodes.count == 1)
        #expect(result.document.expandedText == source)
    }
}
