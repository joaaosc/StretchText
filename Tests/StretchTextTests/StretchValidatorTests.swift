import Testing
@testable import StretchText

private func kinds(_ markup: String, policy: ValidationPolicy = .markup, mode: StretchParser.Mode = .complete) throws -> [String: [StretchIssue.Kind]] {
    let document = try StretchParser.parse(markup, mode: mode)
    var result: [String: [StretchIssue.Kind]] = [:]
    for issue in StretchValidator.validate(document, policy: policy) {
        result[issue.stretchID.description, default: []].append(issue.kind)
    }
    return result
}

private func stretch(_ short: String, _ long: [StretchNode]) -> StretchNode {
    .stretch(Stretch(short: [.text(short)], long: long))
}

@Suite("Validador")
struct StretchValidatorTests {
    @Test("Marcação bem formada não tem problemas", arguments: [
        "The {{build fails on a stale cache.|CI build fails, about one run in five, on a stale dependency cache keyed only by `package.json`.}}",
        "{{A casa caiu.|Ontem, a casa caiu.}} Depois {{nada|nada {{mais|mais ainda}}}}.",
        "Texto sem trechos.",
        "```\n{{a|b}}\n```",
        "Use `{{x}}` {{aqui|aqui e ali}}.",
    ])
    func wellFormed(markup: String) throws {
        #expect(try kinds(markup).isEmpty)
    }

    @Test("Trecho incompleto só recebe .incomplete")
    func incomplete() throws {
        #expect(try kinds("{{a|", mode: .streaming) == ["0": [.incomplete]])
        #expect(try kinds("{{a b|a", mode: .streaming) == ["0": [.incomplete]])
    }

    @Test("Formas vazias")
    func emptyForms() throws {
        #expect(try kinds("{{|algo}}") == ["0": [.emptyShort]])
        #expect(try kinds("{{algo|}}") == ["0": [.emptyLong, .longOmitsShortWords(["algo"])]])
        #expect(try kinds("{{ … |—}}") == ["0": [.emptyShort, .emptyLong]])
    }

    @Test("Forma curta com quebra de linha")
    func shortSpansLines() throws {
        #expect(try kinds("{{a\nb|a\nb c}}") == ["0": [.shortSpansLines]])
        #expect(try kinds("{{a\r\nb|a b c}}") == ["0": [.shortSpansLines]])
    }

    @Test("A longa precisa conter as palavras da curta, em ordem")
    func longOmitsShortWords() throws {
        #expect(try kinds("{{A B C|A X C}}") == ["0": [.longOmitsShortWords(["B"])]])
        #expect(try kinds("{{um dois|dois um}}") == ["0": [.longOmitsShortWords(["dois"])]])
        // Maiúsculas não importam; acentos sim.
        #expect(try kinds("{{Casa caiu|ontem a casa caiu}}").isEmpty)
        #expect(try kinds("{{você|voce mesmo}}") == ["0": [.longOmitsShortWords(["você"])]])
    }

    @Test("A longa é avaliada com os aninhados fechados")
    func nestedClosedForLong() throws {
        #expect(try kinds("{{A B|A {{X|X B}}}}") == ["0": [.longOmitsShortWords(["B"])]])
        #expect(try kinds("{{A B|A {{B|B C}}}}") == ["0": [.longAddsNothing]])
    }

    @Test("A longa precisa acrescentar alguma palavra")
    func longAddsNothing() throws {
        #expect(try kinds("{{A B|a, b!}}") == ["0": [.longAddsNothing]])
    }

    @Test("Trecho em título, tabela ou cerca formada por texto")
    func placements() throws {
        #expect(try kinds("# Título {{a|a b}}") == ["0": [.stretchInHeading]])
        #expect(try kinds("Linha\n  ## {{a|a b}} e {{c|c d}}") == ["0": [.stretchInHeading], "1": [.stretchInHeading]])
        #expect(try kinds("#hashtag {{a|a b}}").isEmpty)
        #expect(try kinds("#{{a b|a b c}} resto").isEmpty)
        #expect(try kinds("##{{a b|a b c}}").isEmpty)
        #expect(try kinds("    # código indentado {{a|a b}}").isEmpty)
        #expect(try kinds("| x {{a|a b}} |") == ["0": [.stretchInTable]])
        #expect(try kinds("# T {{a|a {{b|b c}}}}") == ["0": [.stretchInHeading], "0.0": [.stretchInHeading]])
        #expect(try kinds("# T\n{{a|a b}}").isEmpty)
        #expect(try kinds("# T\u{2028}{{a|a b}}") == ["0": [.stretchInHeading]])

        let fenced = StretchDocument(nodes: [.text("~~~~\n"), stretch("a", [.text("a b")]), .text("\n~~~\n"), stretch("c", [.text("c d")]), .text("\n~~~~\n"), stretch("e", [.text("e f")])])
        let issues = StretchValidator.validate(fenced)
        #expect(issues.map(\.stretchID.description) == ["0", "1"])
        #expect(issues.allSatisfy { $0.kind == .stretchInCodeBlock })
    }

    @Test("O contexto usa a longa dos trechos anteriores, como se estivessem abertos")
    func contextUsesExpandedText() throws {
        #expect(try kinds("{{x|x\n# y}} {{a|a b}}") == ["1": [.stretchInHeading]])
    }

    @Test("Cerca de crases com crase na linha de abertura não é cerca")
    func backtickInfoIsNotFence() {
        let document = StretchDocument(nodes: [.text("```a`\n"), stretch("b", [.text("b c")])])
        #expect(StretchValidator.validate(document).isEmpty)
    }

    @Test("longAddsNothing só aparece quando a longa contém a curta")
    func longAddsNothingIsExclusive() throws {
        #expect(try kinds("{{a b|a}}") == ["0": [.longOmitsShortWords(["b"])]])
    }

    @Test("Política .extractive exige frase da longa e longa com duas frases")
    func extractive() throws {
        #expect(try kinds("{{Segunda frase.|Primeira frase. Segunda frase.}}", policy: .extractive).isEmpty)
        #expect(try kinds("{{Primeira frase|Primeira frase. Segunda frase.}}", policy: .extractive) == ["0": [.shortIsNotSentenceOfLong]])
        #expect(try kinds("{{Só uma|Só uma frase.}}", policy: .extractive) == ["0": [.shortIsNotSentenceOfLong, .longHasSingleSentence]])
        #expect(try kinds("{{Só uma frase.|Só uma frase.}}", policy: .extractive) == ["0": [.longAddsNothing, .longHasSingleSentence]])
        // Quebra de linha dentro da frase vira espaço na curta.
        #expect(try kinds("{{Uma frase longa.|Uma frase\nlonga. Outra.}}", policy: .extractive).isEmpty)
        // A mesma marcação é válida para .markup.
        #expect(try kinds("{{Só uma|Só uma frase.}}").isEmpty)
    }

    @Test("Localização vem do parser; documento montado não tem")
    func locations() throws {
        let parsed = try StretchParser.parse("ok\n  {{a|}}")
        #expect(StretchValidator.validate(parsed).first?.location == StretchText.SourceLocation(line: 2, column: 3))
        let built = StretchDocument(nodes: [stretch("a", [])])
        #expect(StretchValidator.validate(built).map(\.location) == [nil, nil])
    }
}

@Suite("Do texto ao trecho")
struct PipelineTests {
    static let sources: [String] = [
        "",
        "Uma frase só.",
        """
        # Relatório

        O build falha em uma de cada cinco execuções. O cache de dependências usa só o `package.json` como chave. Isso deixa pacotes velhos em uso.

        - Item com duas frases. Não é dobrado.

        | a | b |
        |---|---|
        | 1. Um. | 2 |

        ```swift
        let x = "{{a|b}}"
        ```

        Dr. Silva chegou às 3.15 h. Ele trouxe café... e pão! Fim? Sim.
        Linha seguinte do mesmo parágrafo. E mais uma.
        """,
        "The build fails. It uses a stale cache keyed by `a.b`. See U.S. rules, e.g. this one.\r\n\r\nSecond paragraph. With {braces} and | pipes and \\ backslash. And `code}}`.\r\n",
        "Título\n======\n\nTexto com {{chaves}} soltas. E ~til~.\n\n> Citação. Com duas frases.\n\n---\n\nFim. De verdade.",
        "1️⃣! Segunda frase. Terceira.",
        "Primeira frase. 1️⃣!",
        "Um dois.\u{2028}~~~\n\nPrimeira frase. Segunda frase.",
        "Um dois.\u{85}```\n\nPrimeira frase. Segunda frase.\u{2029}Outra.",
        "| a |\n```x|y\n\nTexto. Dois.",
        "```inline``` texto. Mais uma frase.\n\n```\nTexto. Dois.\n```\n\nFora. Do código.",
    ]

    @Test("Montagem, validação, escrita e leitura preservam o texto", arguments: sources)
    func pipeline(source: String) throws {
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source))
        let document = result.document

        #expect(document.expandedText == source)
        #expect(StretchValidator.validate(document, policy: .extractive).isEmpty)

        let markup = StretchWriter.markup(for: document)
        #expect(try StretchParser.parse(markup) == document)

        var state = StretchState(document: document)
        for id in document.stretchIDs {
            #expect(state.toggle(id) == .opened)
        }
        #expect(state.visibleText == source)
    }

    @Test("O documento montado dobra só parágrafos com duas frases ou mais")
    func foldsOnlyEligibleParagraphs() throws {
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(Self.sources[2]))
        let shorts = result.document.stretchIDs.compactMap { result.document.stretch(at: $0)?.shortText }
        #expect(shorts == [
            "O build falha em uma de cada cinco execuções.",
            "Dr. Silva chegou às 3.15 h.",
        ])
    }
}
