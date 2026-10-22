import Testing
@testable import StretchText

@Suite("Imagem em Markdown")
struct MarkdownImageTests {
    static let uuidName = "4F2C0B1E-6A5D-4C7E-9B1A-3D2E8F7A6C5B.png"

    /// Linha, texto alternativo, origem e título esperados.
    static let valid: [(String, String, String, String?)] = [
        ("![alt](foto.png)", "alt", "foto.png", nil),
        ("![Imagem colada](\(uuidName))", "Imagem colada", uuidName, nil),
        ("![](foto.png)", "", "foto.png", nil),
        ("![Vista da sala](foto.png \"Sala de estar\")", "Vista da sala", "foto.png", "Sala de estar"),
        ("![alt](<minha foto.png>)", "alt", "minha foto.png", nil),
        ("![alt](<minha foto.png> \"Título\")", "alt", "minha foto.png", "Título"),
        ("![alt](<a).png>)", "alt", "a).png", nil),
        ("![alt](foto.png \"Com (parênteses) e 'aspas'\")", "alt", "foto.png", "Com (parênteses) e 'aspas'"),
        ("![alt](foto.png \"\")", "alt", "foto.png", nil),
        ("![ação — 😀](pasta/ação.png)", "ação — 😀", "pasta/ação.png", nil),
        ("![**negrito** e `código`](foto.png)", "**negrito** e `código`", "foto.png", nil),
        ("![logo](https://exemplo.com/a/b.png?x=1&y=2)", "logo", "https://exemplo.com/a/b.png?x=1&y=2", nil),
        ("![alt](foto(1).png)", "alt", "foto(1).png", nil),
        ("![alt](foto.png\"x\")", "alt", "foto.png\"x\"", nil),
        // Recuo de até 3 espaços; espaços e tabs no fim.
        (" ![alt](foto.png)", "alt", "foto.png", nil),
        ("   ![alt](foto.png)", "alt", "foto.png", nil),
        ("![alt](foto.png)   ", "alt", "foto.png", nil),
        ("![alt](foto.png)\t \t", "alt", "foto.png", nil),
        ("  ![alt](foto.png \"t\")  ", "alt", "foto.png", "t"),
        // Espaços e tabs ao redor da origem e do título dentro dos parênteses.
        ("![alt](  foto.png  )", "alt", "foto.png", nil),
        ("![alt]( foto.png \t \"t\" )", "alt", "foto.png", "t"),
        ("![alt](\t<minha foto.png>\t)", "alt", "minha foto.png", nil),
    ]

    @Test("Reconhece a imagem e separa texto alternativo, origem e título", arguments: valid)
    func parsesValidLines(line: String, alt: String, source: String, title: String?) {
        #expect(MarkdownImage.parse(line) == MarkdownImage(alt: alt, source: source, title: title))
    }

    /// Linhas de uma linha só que não são uma imagem sozinha.
    static let invalid: [String] = [
        // Vazias.
        "", " ", "   ", "\t",
        // Não é imagem.
        "texto", "[alt](foto.png)", "!alt](foto.png)", "! [alt](foto.png)", "!\\[alt](foto.png)", "<![alt](foto.png)>",
        // Texto antes.
        "Veja ![alt](foto.png)", "- ![alt](foto.png)", "> ![alt](foto.png)", "# ![alt](foto.png)",
        "| ![alt](foto.png) |", "\u{FEFF}![alt](foto.png)", "\u{00A0}![alt](foto.png)",
        // Texto depois.
        "![alt](foto.png) depois", "![alt](foto.png).", "![alt](foto.png)[link](outro)", "![alt](foto.png)\u{00A0}",
        // Duas imagens, imagem dentro de link ou dentro de outra.
        "![a](a.png)![b](b.png)", "![a](a.png) ![b](b.png)", "[![alt](foto.png)](https://exemplo.com)",
        "![a ![b](b.png) c](a.png)",
        // Incompleta.
        "!", "![", "![alt", "![alt]", "![alt](", "![alt](foto.png", "![alt](foto.png \"t\"", "![alt] (foto.png)",
        "![alt](<foto.png)", "![alt](<foto.png", "![alt](foto(1.png)", "![alt](foto)1.png)",
        // O texto alternativo não tem `]`.
        "![a]b](foto.png)", "![a\\]b](foto.png)",
        // Origem vazia ou com espaço fora de `<` e `>`.
        "![alt]()", "![alt]( )", "![alt](<>)", "![alt](< >)", "![alt](minha foto.png)", "![alt](<a b>c)",
        // Título fora do formato.
        "![alt](foto.png \"t)", "![alt](foto.png 't')", "![alt](foto.png (t))", "![alt](foto.png \"t\" x)",
        "![alt](foto.png \"a\" \"b\")", "![alt](<foto.png>\"t\")", "![alt](foto.png \"say \\\"oi\\\"\")",
        // Indentação de 4 colunas ou mais.
        "    ![alt](foto.png)", "\t![alt](foto.png)", " \t![alt](foto.png)", "  \t![alt](foto.png)",
    ]

    @Test("Qualquer outra linha devolve nil", arguments: invalid)
    func rejectsInvalidLines(_ line: String) {
        #expect(MarkdownImage.parse(line) == nil)
    }

    @Test("Quebra de linha em qualquer ponto devolve nil: é uma linha só", arguments: [
        "![alt](foto.png)\n", "![alt](foto.png)\r\n", "![alt](foto.png)\r", "\n![alt](foto.png)",
        "![al\nt](foto.png)", "![alt](fo\nto.png)", "![alt](<fo\nto.png>)", "![alt](foto.png \"t\nt\")",
        "![a](a.png)\n![b](b.png)", "![alt]\n(foto.png)", "![alt](foto.png\n)",
    ])
    func rejectsLineBreaks(_ line: String) {
        #expect(MarkdownImage.parse(line) == nil)
    }

    @Test("Lê qualquer StringProtocol: String e Substring dão o mesmo resultado")
    func acceptsAnyStringProtocol() {
        let text = "antes\n![alt](foto.png \"t\")\ndepois"
        let line = text.split(separator: "\n")[1]
        #expect(MarkdownImage.parse(line) == MarkdownImage(alt: "alt", source: "foto.png", title: "t"))
        #expect(MarkdownImage.parse(line) == MarkdownImage.parse(String(line)))
        #expect(MarkdownImage.parse(text) == nil)
    }

    @Test("Origem com texto UTF-8 de vários bytes volta inteira")
    func multibyteContentIsPreserved() throws {
        let image = try #require(MarkdownImage.parse("![日本語 👩‍👩‍👧‍👦](<写真 😀.png> \"título — é\")"))
        #expect(image.alt == "日本語 👩‍👩‍👧‍👦")
        #expect(image.source == "写真 😀.png")
        #expect(image.title == "título — é")
    }

    @Test("Imagens com os mesmos campos são iguais e entram em conjuntos")
    func hashableValue() {
        let first = MarkdownImage(alt: "a", source: "b.png")
        #expect(first == MarkdownImage(alt: "a", source: "b.png", title: nil))
        #expect(first != MarkdownImage(alt: "a", source: "b.png", title: "t"))
        #expect(first != MarkdownImage(alt: "x", source: "b.png"))
        #expect(Set([first, MarkdownImage(alt: "a", source: "b.png")]).count == 1)
    }

    @Test("O segmentador e parse concordam: a linha é bloco .image se, e só se, parse a aceita")
    func segmenterAgreesWithParse() {
        let lines = Self.valid.map(\.0) + Self.invalid + ["![alt](foto.png)"]
        for line in lines {
            let kinds = TextSegmenter.segment(line).segments.map(\.kind).filter { $0 != .blank }
            let isImage = MarkdownImage.parse(line) != nil
            // Linhas com 4 colunas de recuo viram código antes de chegar à imagem.
            #expect((kinds == [.image]) == isImage, "linha: \(line.debugDescription), blocos: \(kinds)")
        }
    }

    @Test("Listar as imagens de um texto pelos blocos .image deixa de fora as que estão em código")
    func listsImagesLikeTheReadingView() {
        let text = """
            # Nota

            ![Primeira](a.png)

            Texto com ![no meio](b.png) da frase.

            ```markdown
            ![Em código](c.png)
            ```

            - item
            ![Depois do item](d.png "título")

                ![Indentada](e.png)

            ![Última](<f g.png>)
            """
        let images = TextSegmenter.segment(text).segments
            .filter { $0.kind == .image }
            .compactMap { MarkdownImage.parse($0.text) }
        #expect(images == [
            MarkdownImage(alt: "Primeira", source: "a.png"),
            MarkdownImage(alt: "Depois do item", source: "d.png", title: "título"),
            MarkdownImage(alt: "Última", source: "f g.png"),
        ])
    }
}
