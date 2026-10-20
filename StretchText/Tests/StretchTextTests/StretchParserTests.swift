import Testing
@testable import StretchText

/// O módulo `Testing` também tem um `SourceLocation`.
private typealias Location = StretchText.SourceLocation

private func parse(_ markup: String, _ mode: StretchParser.Mode = .complete) throws -> StretchDocument {
    try StretchParser.parse(markup, mode: mode)
}

private func stretch(
    _ short: [InlineNode],
    _ long: [StretchNode],
    _ progress: Stretch.Progress = .complete
) -> StretchNode {
    .stretch(Stretch(short: short, long: long, progress: progress))
}

private func id(_ text: String) -> StretchID {
    guard let id = StretchID(text) else { preconditionFailure("ID inválido no teste: \(text)") }
    return id
}

private func at(_ line: Int, _ column: Int) -> Location {
    Location(line: line, column: column)
}

private let bothModes: [StretchParser.Mode] = [.complete, .streaming]

@Suite("Parser de marcação")
struct StretchParserTests {
    // MARK: - Texto e trechos

    @Test("A versão da gramática é 1")
    func grammarVersion() {
        #expect(StretchParser.grammarVersion == 1)
    }

    @Test("Texto puro vira um único nó de texto", arguments: [
        "Olá, mundo.", "linha 1\nlinha 2", "  espaços  ", "emoji 👨‍👩‍👧 e acento e\u{301}",
    ])
    func plainText(_ text: String) throws {
        let document = try parse(text)
        #expect(document.nodes == [.text(text)])
        #expect(document.stretchIDs.isEmpty)
        #expect(document.sourceLocations.isEmpty)
    }

    @Test("Texto vazio vira documento vazio", arguments: bothModes)
    func emptyText(_ mode: StretchParser.Mode) throws {
        let document = try parse("", mode)
        #expect(document.nodes.isEmpty)
        #expect(document.isComplete)
    }

    @Test("`}}`, `|` e `{` fora de trecho são texto", arguments: [
        "a }} b", "a | b", "a { b", "a } b", "}}}", "|||", "{ { } }", "x{y}z",
    ])
    func looseDelimitersAreText(_ text: String) throws {
        #expect(try parse(text).nodes == [.text(text)])
    }

    @Test("Trecho simples entre textos")
    func simpleStretch() throws {
        let document = try parse("Antes {{curta|longa}} depois")
        #expect(document.nodes == [
            .text("Antes "),
            stretch([.text("curta")], [.text("longa")]),
            .text(" depois"),
        ])
        #expect(document.isComplete)
        #expect(document.sourceLocations == [id("0"): at(1, 7)])
    }

    @Test("Formas vazias são aceitas")
    func emptyForms() throws {
        #expect(try parse("{{|}}").nodes == [stretch([], [])])
        #expect(try parse("{{a|}}").nodes == [stretch([.text("a")], [])])
        #expect(try parse("{{|b}}").nodes == [stretch([], [.text("b")])])
    }

    @Test("Trechos vizinhos recebem IDs consecutivos")
    func siblingStretches() throws {
        let document = try parse("{{a|b}}{{c|d}} {{e|f}}")
        #expect(document.stretchIDs.map(\.description) == ["0", "1", "2"])
        #expect(document.sourceLocations[id("1")] == at(1, 8))
        #expect(document.sourceLocations[id("2")] == at(1, 16))
    }

    @Test("Trecho aninhado em dois níveis: IDs 0, 0.0 e 1")
    func nestedTwoLevels() throws {
        let document = try parse("{{a|{{b|c}}}} {{d|e}}")
        let inner = stretch([.text("b")], [.text("c")])
        #expect(document.nodes == [
            stretch([.text("a")], [inner]),
            .text(" "),
            stretch([.text("d")], [.text("e")]),
        ])
        #expect(document.stretchIDs.map(\.description) == ["0", "0.0", "1"])
        #expect(document.sourceLocations == [id("0"): at(1, 1), id("0.0"): at(1, 5), id("1"): at(1, 15)])
    }

    @Test("Trecho aninhado em três níveis")
    func nestedThreeLevels() throws {
        let document = try parse("{{a|b {{c|d {{e|f}} g}} h}} {{i|j}}")
        let deepest = stretch([.text("e")], [.text("f")])
        let middle = stretch([.text("c")], [.text("d "), deepest, .text(" g")])
        #expect(document.nodes == [
            stretch([.text("a")], [.text("b "), middle, .text(" h")]),
            .text(" "),
            stretch([.text("i")], [.text("j")]),
        ])
        #expect(document.stretchIDs.map(\.description) == ["0", "0.0", "0.0.0", "1"])
        #expect(document.sourceLocations == [
            id("0"): at(1, 1), id("0.0"): at(1, 7), id("0.0.0"): at(1, 13), id("1"): at(1, 29),
        ])
    }

    @Test("Irmãos na forma longa são numerados em ordem de texto")
    func nestedSiblings() throws {
        let document = try parse("{{a|{{b|c}} e {{f|g}}}}")
        #expect(document.stretchIDs.map(\.description) == ["0", "0.0", "0.1"])
        #expect(document.stretch(at: id("0.1")) == Stretch(short: [.text("f")], long: [.text("g")]))
    }

    @Test("Na forma longa, `|` é texto: `{{a|b|c}}` tem longa `b|c`")
    func pipeInLongForm() throws {
        #expect(try parse("{{a|b|c}}").nodes == [stretch([.text("a")], [.text("b|c")])])
        #expect(try parse("{{a|||}}").nodes == [stretch([.text("a")], [.text("||")])])
    }

    @Test("O primeiro `}}` do nível fecha; o resto é texto do nível de fora")
    func firstClosingWins() throws {
        #expect(try parse("{{a|b}}c}}").nodes == [stretch([.text("a")], [.text("b")]), .text("c}}")])
        #expect(try parse("{{a|b}}}").nodes == [stretch([.text("a")], [.text("b")]), .text("}")])
        #expect(try parse("{{a|b}} | c").nodes == [stretch([.text("a")], [.text("b")]), .text(" | c")])
    }

    @Test("`{{{` abre o trecho nos dois primeiros e a terceira chave é texto")
    func tripleBrace() throws {
        #expect(try parse("{{{a|b}}").nodes == [stretch([.text("{a")], [.text("b")])])
    }

    @Test("`{` e `}` isolados dentro das formas são texto")
    func singleBracesInside() throws {
        #expect(try parse("{{a{b}c|d{e}f}}").nodes == [stretch([.text("a{b}c")], [.text("d{e}f")])])
    }

    // MARK: - Escapes

    @Test("Escape produz o caractere literal", arguments: [
        ("\\\\", "\\"), ("\\{", "{"), ("\\}", "}"), ("\\|", "|"), ("\\`", "`"), ("\\~", "~"),
    ])
    func escapes(markup: String, expected: String) throws {
        #expect(try parse("a\(markup)b").nodes == [.text("a\(expected)b")])
    }

    @Test("Barra invertida antes de caractere comum fica literal", arguments: [
        "C:\\pasta", "\\a", "\\ ", "fim\\", "\\\n", "\\é", "\\1",
    ])
    func plainBackslash(_ text: String) throws {
        #expect(try parse(text).nodes == [.text(text)])
    }

    @Test("Escapes impedem abrir trecho")
    func escapesPreventStretch() throws {
        #expect(try parse("\\{\\{x\\}\\}").nodes == [.text("{{x}}")])
        // `\{` gasta a primeira chave; a segunda fica sozinha.
        #expect(try parse("\\{{a|b}}").nodes == [.text("{{a|b}}")])
        // `\\` vira uma barra e a abertura seguinte vale.
        #expect(try parse("\\\\{{a|b}}").nodes == [.text("\\"), stretch([.text("a")], [.text("b")])])
    }

    @Test("Escapes funcionam nas duas formas e protegem `|` e `}}`")
    func escapesInsideForms() throws {
        #expect(try parse("{{a\\|b|c\\}}d}}").nodes == [stretch([.text("a|b")], [.text("c}}d")])])
    }

    @Test("Escapes impedem abrir código em linha, cerca de crases e cerca de tis")
    func escapesPreventCode() throws {
        #expect(try parse("\\`a`").nodes == [.text("`a`")])
        #expect(try parse("\\`\\`\\`\nx\n").nodes == [.text("```\nx\n")])
        #expect(try parse("\\~~~\nx").nodes == [.text("~~~\nx")])
    }

    @Test("Escapes não valem dentro de código")
    func escapesInsideCode() throws {
        // A barra antes da crase de fechamento não a protege.
        #expect(try parse("`a\\`").nodes == [.code("`a\\`")])
        #expect(try parse("`\\{ \\|`").nodes == [.code("`\\{ \\|`")])
        #expect(try parse("```\n\\{ \\|\n```").nodes == [.code("```\n\\{ \\|\n```")])
    }

    // MARK: - Código em linha

    @Test("Código em linha guarda crases e conteúdo crus e esconde os delimitadores")
    func inlineCode() throws {
        let document = try parse("x `{{a|b}}` y")
        #expect(document.nodes == [.text("x "), .code("`{{a|b}}`"), .text(" y")])
        #expect(document.stretchIDs.isEmpty)
    }

    @Test("Código em linha dentro da forma curta e da longa")
    func inlineCodeInsideStretch() throws {
        let document = try parse("{{use `a|b`|use `a|b` agora}}")
        #expect(document.nodes == [
            stretch(
                [.text("use "), .code("`a|b`")],
                [.text("use "), .code("`a|b`"), .text(" agora")]
            ),
        ])
        #expect(try parse("{{a|`b}}`}}").nodes == [stretch([.text("a")], [.code("`b}}`")])])
        #expect(try parse("{{`{{x`|y}}").nodes == [stretch([.code("`{{x`")], [.text("y")])])
    }

    @Test("Código em linha pode atravessar uma quebra de linha", arguments: ["`a\nb`", "`a\r\nb`", "`a\n b`"])
    func inlineCodeAcrossLine(_ markup: String) throws {
        #expect(try parse(markup).nodes == [.code(markup)])
    }

    @Test("Crases sem par são texto", arguments: [
        "`", "a ` b", "a `` b ` c", "a ``` b `` c", "x```",
        "`a\n\nb`", "`a\n  \nb`", "`a\n \t\nb`", "`a\r\n\r\nb`",
    ])
    func unpairedBackticks(_ text: String) throws {
        #expect(try parse(text).nodes == [.text(text)])
    }

    @Test("A sequência de fechamento tem exatamente o tamanho da de abertura")
    func backtickRunLengths() throws {
        #expect(try parse("``a`b``").nodes == [.code("``a`b``")])
        #expect(try parse("`a``b`").nodes == [.code("`a``b`")])
        #expect(try parse("```a``b```").nodes == [.code("```a``b```")])
        #expect(try parse("`` ` ``").nodes == [.code("`` ` ``")])
        #expect(try parse("a ```b``` c").nodes == [.text("a "), .code("```b```"), .text(" c")])
    }

    @Test("Códigos em linha seguidos e crase final sem par")
    func severalInlineCodes() throws {
        #expect(try parse("a `b` `c` d").nodes == [
            .text("a "), .code("`b`"), .text(" "), .code("`c`"), .text(" d"),
        ])
        #expect(try parse("`a` b `").nodes == [.code("`a`"), .text(" b `")])
    }

    @Test("Crase sem par não impede a leitura dos trechos")
    func unpairedBacktickKeepsStretches() throws {
        #expect(try parse("`{{a|b}}").nodes == [.text("`"), stretch([.text("a")], [.text("b")])])
    }

    // MARK: - Cerca de código

    @Test("Cerca de crases e de tis esconde os delimitadores", arguments: [
        "```\n{{a|b}} | }}\n```", "~~~\n{{a|b}} | }}\n~~~", "```swift\nlet a = 1\n```",
        "````\nx\n`````", "~~~~\nx\n~~~", "```\n\n\nx\n```",
    ])
    func fenceHidesDelimiters(_ markup: String) throws {
        let document = try parse(markup)
        #expect(document.nodes == [.code(markup)])
    }

    @Test("A cerca vai da abertura ao fim da cerca de fechamento, sem a quebra de linha")
    func fenceBounds() throws {
        #expect(try parse("Antes\n```\n}}\n```\nDepois").nodes == [
            .text("Antes\n"), .code("```\n}}\n```"), .text("\nDepois"),
        ])
        #expect(try parse("a\r\n```\r\nx\r\n```\r\ny").nodes == [
            .text("a\r\n"), .code("```\r\nx\r\n```"), .text("\r\ny"),
        ])
    }

    @Test("Até 3 espaços antes da cerca ficam no texto anterior e os espaços depois do fechamento no seguinte")
    func fenceSpaces() throws {
        // Decisão: o nó `.code` vai do primeiro ao último caractere de cerca.
        #expect(try parse("  ```\nx\n  ```\ny").nodes == [
            .text("  "), .code("```\nx\n  ```"), .text("\ny"),
        ])
        #expect(try parse("```\nx\n```   \ny").nodes == [.code("```\nx\n```"), .text("   \ny")])
        #expect(try parse("   ~~~\nx\n   ~~~").nodes == [.text("   "), .code("~~~\nx\n   ~~~")])
    }

    @Test("Com 4 espaços ou fora do início de linha não há cerca")
    func notAFence() throws {
        // Sem cerca, o `{{a|b}}` de baixo é lido como trecho; com cerca seria código.
        let indented = try parse("    ```\n\n{{a|b}}\n```")
        #expect(indented.nodes == [
            .text("    ```\n\n"), stretch([.text("a")], [.text("b")]), .text("\n"), .code("```"),
        ])
        let midLine = try parse("x ```\n\n{{a|b}}")
        #expect(midLine.nodes == [.text("x ```\n\n"), stretch([.text("a")], [.text("b")])])
    }

    @Test("A cerca só fecha com linha da mesma cerca, igual ou maior, e nada depois")
    func fenceClosing() throws {
        let tail = "\n{{c|d}}"
        // Cerca menor não fecha.
        #expect(try parse("````\nx\n```\n{{a|b}}\n````" + tail).nodes == [
            .code("````\nx\n```\n{{a|b}}\n````"), .text("\n"), stretch([.text("c")], [.text("d")]),
        ])
        // Outro caractere não fecha.
        #expect(try parse("```\nx\n~~~\n{{a|b}}\n```" + tail).nodes == [
            .code("```\nx\n~~~\n{{a|b}}\n```"), .text("\n"), stretch([.text("c")], [.text("d")]),
        ])
        // Texto depois da cerca ou 4 espaços antes não fecham.
        #expect(try parse("```\nx\n``` y\n{{a|b}}\n```" + tail).nodes == [
            .code("```\nx\n``` y\n{{a|b}}\n```"), .text("\n"), stretch([.text("c")], [.text("d")]),
        ])
        #expect(try parse("```\nx\n    ```\n{{a|b}}\n```" + tail).nodes == [
            .code("```\nx\n    ```\n{{a|b}}\n```"), .text("\n"), stretch([.text("c")], [.text("d")]),
        ])
    }

    @Test("Cerca sem fechamento vai até o fim do texto", arguments: bothModes)
    func unterminatedFence(_ mode: StretchParser.Mode) throws {
        #expect(try parse("texto\n```\n{{a|b", mode).nodes == [.text("texto\n"), .code("```\n{{a|b")])
        #expect(try parse("```\nx\n", mode).nodes == [.code("```\nx\n")])
        #expect(try parse("~~~", mode).nodes == [.code("~~~")])
    }

    @Test("Cerca sem fechamento esconde o `}}` e deixa o trecho aberto")
    func unterminatedFenceKeepsStretchOpen() throws {
        let markup = "{{a|\n```\nx\n}}"
        #expect(throws: StretchParseError.unclosedStretch(at(1, 1))) { try parse(markup) }
        let document = try parse(markup, .streaming)
        #expect(document.nodes == [
            stretch([.text("a")], [.text("\n"), .code("```\nx\n}}")], .receivingLong),
        ])
    }

    @Test("Cerca dentro da forma longa")
    func fenceInLongForm() throws {
        let document = try parse("{{a|\n```\n}} |\n```\n}}")
        #expect(document.nodes == [
            stretch([.text("a")], [.text("\n"), .code("```\n}} |\n```"), .text("\n")]),
        ])
    }

    @Test("Cerca dentro da forma curta")
    func fenceInShortForm() throws {
        let document = try parse("{{a\n```\n| }}\n```\n|b}}")
        #expect(document.nodes == [
            stretch([.text("a\n"), .code("```\n| }}\n```"), .text("\n")], [.text("b")]),
        ])
    }

    // MARK: - Erros

    @Test("`{{nome}}` sem `|` é missingSeparator, nos dois modos", arguments: bothModes)
    func missingSeparator(_ mode: StretchParser.Mode) {
        let cases: [(String, Location)] = [
            ("{{nome}}", at(1, 1)),
            ("ab\n  {{nome}}", at(2, 3)),
            ("{{a|{{b}}}}", at(1, 5)),
            ("{{a|b {{c}} d}}", at(1, 7)),
            ("{{a}}", at(1, 1)),
        ]
        for (markup, location) in cases {
            #expect(throws: StretchParseError.missingSeparator(location), "entrada: \(markup)") {
                try parse(markup, mode)
            }
        }
    }

    @Test("`{{` na forma curta é stretchInShortForm, nos dois modos", arguments: bothModes)
    func stretchInShortForm(_ mode: StretchParser.Mode) {
        let cases: [(String, Location)] = [
            ("{{a {{b|c}} d|e}}", at(1, 5)),
            ("{{{{", at(1, 3)),
            ("{{a|b}} {{c {{d", at(1, 13)),
            ("x\n{{a {{", at(2, 5)),
        ]
        for (markup, location) in cases {
            #expect(throws: StretchParseError.stretchInShortForm(location), "entrada: \(markup)") {
                try parse(markup, mode)
            }
        }
    }

    @Test("Código e escape protegem contra stretchInShortForm")
    func shortFormProtected() throws {
        #expect(try parse("{{a \\{\\{|b}}").nodes == [stretch([.text("a {{")], [.text("b")])])
        #expect(try parse("{{a `{{`|b}}").nodes == [stretch([.text("a "), .code("`{{`")], [.text("b")])])
    }

    @Test("Fim do texto com trecho aberto lança unclosedStretch em .complete")
    func unclosedInCompleteMode() {
        let cases: [(String, Location)] = [
            ("{{a", at(1, 1)),
            ("{{a|", at(1, 1)),
            ("{{a|b", at(1, 1)),
            ("x {{a|{{b|c", at(1, 3)),
            ("{{a|b {{c|d}} e", at(1, 1)),
            ("{{a|b}} {{c|d", at(1, 9)),
            ("ok\r\n\r\n{{a|b", at(3, 1)),
        ]
        for (markup, location) in cases {
            #expect(throws: StretchParseError.unclosedStretch(location), "entrada: \(markup)") {
                try parse(markup, .complete)
            }
        }
    }

    // MARK: - Modo streaming

    @Test("Em .streaming, trecho aberto fica incompleto conforme o `|` chegou")
    func streamingProgress() throws {
        let cases: [(String, [StretchNode])] = [
            ("{{", [stretch([], [], .receivingShort)]),
            ("{{|", [stretch([], [], .receivingLong)]),
            ("{{a", [stretch([.text("a")], [], .receivingShort)]),
            ("{{a|", [stretch([.text("a")], [], .receivingLong)]),
            ("{{a|b", [stretch([.text("a")], [.text("b")], .receivingLong)]),
            ("{{a|b}", [stretch([.text("a")], [.text("b}")], .receivingLong)]),
            ("{{a}", [stretch([.text("a}")], [], .receivingShort)]),
            ("x {{a|b}} {{c", [
                .text("x "), stretch([.text("a")], [.text("b")]), .text(" "),
                stretch([.text("c")], [], .receivingShort),
            ]),
        ]
        for (markup, nodes) in cases {
            let document = try parse(markup, .streaming)
            #expect(document.nodes == nodes, "entrada: \(markup)")
            #expect(!document.isComplete, "entrada: \(markup)")
        }
    }

    @Test("Em .streaming, todos os trechos abertos na pilha ficam incompletos")
    func streamingNested() throws {
        let cases: [(String, [StretchNode])] = [
            ("{{a|b {{c", [
                stretch([.text("a")], [.text("b "), stretch([.text("c")], [], .receivingShort)], .receivingLong),
            ]),
            ("{{a|b {{c|d", [
                stretch([.text("a")], [.text("b "), stretch([.text("c")], [.text("d")], .receivingLong)], .receivingLong),
            ]),
            ("{{a|b {{c|d}} e", [
                stretch(
                    [.text("a")],
                    [.text("b "), stretch([.text("c")], [.text("d")]), .text(" e")],
                    .receivingLong
                ),
            ]),
            ("{{a|{{b|{{c", [
                stretch([.text("a")], [
                    stretch([.text("b")], [
                        stretch([.text("c")], [], .receivingShort),
                    ], .receivingLong),
                ], .receivingLong),
            ]),
        ]
        for (markup, nodes) in cases {
            let document = try parse(markup, .streaming)
            #expect(document.nodes == nodes, "entrada: \(markup)")
        }
        let deep = try parse("{{a|{{b|{{c", .streaming)
        #expect(deep.stretchIDs.map(\.description) == ["0", "0.0", "0.0.0"])
        #expect(deep.sourceLocations[id("0.0.0")] == at(1, 9))
    }

    @Test("Em .streaming, texto completo dá o mesmo documento que em .complete", arguments: [
        "", "texto", "{{a|b}}", "x {{a|{{b|c}} d}} y `{{z|w}}` ```\n}}\n```", "{{a|b}} }} | \\{ \\\\",
    ])
    func streamingEqualsCompleteWhenClosed(_ markup: String) throws {
        let complete = try parse(markup, .complete)
        let streaming = try parse(markup, .streaming)
        #expect(complete == streaming)
        #expect(complete.sourceLocations == streaming.sourceLocations)
        #expect(streaming.isComplete)
    }

    @Test("Ao crescer em prefixos, IDs, localizações e trechos já recebidos não mudam")
    func streamingPrefixesAreStable() throws {
        let markup = "Início {{um|um e dois {{dois|dois e três \\| \\}}} fim}} meio `x` {{três|três e quatro}}.\n"
            + "Cerca:\n```\ncódigo\n```\n{{fim|fim de tudo}}"
        let scalars = Array(markup.unicodeScalars)
        var previous: StretchDocument?
        for length in 0...scalars.count {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[..<length])
            let prefix = String(view)
            let document: StretchDocument
            do {
                document = try parse(prefix, .streaming)
            } catch {
                Issue.record("prefixo \(length) lançou \(error): \(prefix.debugDescription)")
                continue
            }
            if let previous {
                for oldID in previous.stretchIDs {
                    let old = try #require(previous.stretch(at: oldID))
                    let new = try #require(document.stretch(at: oldID), "ID \(oldID) sumiu no prefixo \(length)")
                    #expect(document.sourceLocation(of: oldID) == previous.sourceLocation(of: oldID), "ID \(oldID), prefixo \(length)")
                    if old.progress == .complete {
                        #expect(new == old, "ID \(oldID) mudou depois de completo, prefixo \(length)")
                    }
                    if old.progress != .receivingShort {
                        #expect(new.short == old.short, "curta de \(oldID) mudou, prefixo \(length)")
                    }
                }
            }
            previous = document
        }
        let final = try #require(previous)
        #expect(final == (try parse(markup, .complete)))
        #expect(final.stretchIDs.map(\.description) == ["0", "0.0", "1", "2"])
    }

    @Test("Erros definitivos aparecem quando o trecho os mostra e continuam nos prefixos seguintes", arguments: [
        ("{{nome}} resto", "{{nome}}", StretchParseError.missingSeparator(at(1, 1))),
        ("ab {{a {{b|c}} d|e}}", "ab {{a {{", StretchParseError.stretchInShortForm(at(1, 8))),
    ])
    func definitiveErrors(markup: String, trigger: String, expected: StretchParseError) throws {
        let scalars = Array(markup.unicodeScalars)
        let triggerLength = trigger.unicodeScalars.count
        for length in 0...scalars.count {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[..<length])
            let prefix = String(view)
            if length < triggerLength {
                #expect(throws: Never.self, "prefixo \(length) não devia lançar") {
                    try parse(prefix, .streaming)
                }
            } else {
                #expect(throws: expected, "prefixo \(length) devia lançar") {
                    try parse(prefix, .streaming)
                }
            }
        }
    }

    @Test("Limite conhecido: código com delimitadores só vale quando a crase de fechamento chega")
    func unpairedBacktickIsProvisional() throws {
        // Enquanto a crase de fechamento não chegou, a crase é texto e o conteúdo é lido
        // como marcação. Quando ela chega, o trecho que parecia existir vira código.
        let before = try parse("Antes `{{a|b}}", .streaming)
        #expect(before.stretchIDs.map(\.description) == ["0"])
        let after = try parse("Antes `{{a|b}}`", .streaming)
        #expect(after.stretchIDs.isEmpty)
        #expect(after.nodes == [.text("Antes "), .code("`{{a|b}}`")])
    }

    @Test("Limite conhecido: no streaming, erro depois de crase sem par pode sumir quando o par chega")
    func unpairedBacktickMakesErrorsProvisional() throws {
        #expect(throws: StretchParseError.missingSeparator(at(1, 4))) { try parse("`a {{b}} c", .streaming) }
        #expect(try parse("`a {{b}} c`", .streaming).nodes == [.code("`a {{b}} c`")])
        #expect(throws: StretchParseError.stretchInShortForm(at(1, 12))) { try parse("Use `a {{b {{c|d}} e", .streaming) }
        #expect(try parse("Use `a {{b {{c|d}} e`", .streaming).stretchIDs.isEmpty)
    }

    // MARK: - Localizações

    @Test("A coluna conta Character, com acento combinante e emoji composto antes do `{{`")
    func columnCountsCharacters() throws {
        let prefix = "Ola\u{301} \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} e\u{301} "
        #expect(prefix.count == 8)
        #expect(prefix.unicodeScalars.count > 12)
        let document = try parse(prefix + "{{a|b}} e {{c|d}}")
        #expect(document.sourceLocations[id("0")] == at(1, 9))
        #expect(document.sourceLocations[id("1")] == at(1, 9 + 7 + 3))
        #expect(throws: StretchParseError.missingSeparator(at(1, 9))) { try parse(prefix + "{{nome}}") }
        #expect(throws: StretchParseError.unclosedStretch(at(1, 9))) { try parse(prefix + "{{a|b") }
    }

    @Test("CRLF conta como uma quebra de linha")
    func crlfCountsOnce() throws {
        #expect("\r\n".count == 1)
        let document = try parse("linha 1\r\nlinha 2\r\n  {{a|b}}\r\n{{c|d}}")
        #expect(document.sourceLocations == [id("0"): at(3, 3), id("1"): at(4, 1)])
        #expect(throws: StretchParseError.missingSeparator(at(2, 3))) { try parse("a\r\n  {{nome}}") }
    }

    @Test("Só \\n, \\r e \\r\\n são quebras de linha, como no CommonMark", arguments: [
        ("a\rb\n{{x|y}}", 3, 1), ("a\n{{x|y}}", 2, 1), ("a\u{2028}{{x|y}}", 1, 3), ("a\u{85}\u{2029}{{x|y}}", 1, 4),
    ])
    func otherLineBreaks(markup: String, line: Int, column: Int) throws {
        #expect(try parse(markup).sourceLocations[id("0")] == at(line, column))
    }

    @Test("Quebras de linha do parser")
    func lineBreakScalars() {
        var breaks: [UInt32] = []
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            if MarkupScalar.isLineBreak(scalar) { breaks.append(value) }
        }
        #expect(breaks == [0x0A, 0x0D])
        #expect(MarkupScalar.isLineBreak(Character("\r\n")))
        #expect(!MarkupScalar.isLineBreak(Character("\u{2028}")))
    }

    @Test("Separador de linha Unicode não abre cerca")
    func unicodeLineSeparatorDoesNotStartFence() throws {
        let document = try parse("a\u{2028}```\n{{x|y}}")
        #expect(document.stretchIDs.map(\.description) == ["0"])
    }

    @Test("Cerca de crases com crase na linha de abertura é código em linha")
    func backtickInFenceInfo() throws {
        let document = try parse("```inline``` texto {{a|a b}} fim")
        #expect(document.nodes == [.code("```inline```"), .text(" texto "), stretch([.text("a")], [.text("a b")]), .text(" fim")])
        let tilde = try parse("~~~ a`b\n{{a|b}}\n~~~")
        #expect(tilde.nodes == [.code("~~~ a`b\n{{a|b}}\n~~~")])
    }

    @Test("Delimitador seguido de acento combinante continua sendo delimitador")
    func combiningMarkAfterDelimiter() throws {
        let document = try parse("{{a|b}}\u{301} \\{\u{301}")
        #expect(document.nodes == [stretch([.text("a")], [.text("b")]), .text("\u{301} {\u{301}")])
    }

    // MARK: - Propriedades gerais

    @Test("Todas as entradas curtas dão o mesmo resultado nos dois modos, exceto trecho aberto")
    func modesAgree() {
        let alphabet = ["{", "}", "|", "\\", "`", "~", "a", " ", "\n"]
        var failures: [String] = []
        forEachString(over: alphabet, maxLength: 5) { markup in
            let complete = Result { () throws(StretchParseError) -> StretchDocument in
                try StretchParser.parse(markup, mode: .complete)
            }
            let streaming = Result { () throws(StretchParseError) -> StretchDocument in
                try StretchParser.parse(markup, mode: .streaming)
            }
            switch (complete, streaming) {
            case (.success(let lhs), .success(let rhs)):
                if lhs != rhs || !rhs.isComplete || lhs.sourceLocations != rhs.sourceLocations {
                    failures.append(markup.debugDescription)
                }
            case (.failure(.unclosedStretch), .success(let document)):
                if document.isComplete { failures.append(markup.debugDescription) }
            case (.failure(let lhs), .failure(let rhs)):
                if lhs != rhs { failures.append(markup.debugDescription) }
            default:
                failures.append(markup.debugDescription)
            }
        }
        #expect(failures.isEmpty, "primeiras falhas: \(failures.prefix(5))")
    }

    // MARK: - Desempenho

    @Test("Entrada grande com muitos trechos é lida em tempo razoável", .timeLimit(.minutes(1)))
    func largeInput() throws {
        let unit = "texto {{curta|longa `x` \\| mais {{a|b}}}} e }} solto\n"
        let document = try parse(String(repeating: unit, count: 20_000))
        #expect(document.stretchIDs.count == 40_000)
    }

    @Test("Muitas sequências de crases de tamanhos diferentes e sem par são lidas em tempo razoável", .timeLimit(.minutes(1)))
    func manyUnpairedBacktickRuns() throws {
        var markup = ""
        for length in 1...300 {
            markup += String(repeating: "`", count: length) + " a "
        }
        #expect(try parse(markup).nodes == [.text(markup)])
    }

    @Test("Aninhamento até o limite é lido", arguments: bothModes)
    func nestingUpToLimit(mode: StretchParser.Mode) throws {
        let depth = StretchParser.maximumNestingDepth
        let markup = String(repeating: "{{a|", count: depth) + "x" + String(repeating: "}}", count: depth)
        let document = try parse(markup, mode)
        #expect(document.stretchIDs.count == depth)
        #expect(document.stretchIDs.last?.depth == depth)
        let open = try parse(String(repeating: "{{a|", count: depth), .streaming)
        #expect(!open.isComplete)
    }

    @Test("Aninhamento além do limite é nestingTooDeep, sem esgotar a pilha", .timeLimit(.minutes(1)), arguments: bothModes)
    func nestingBeyondLimit(mode: StretchParser.Mode) {
        let depth = StretchParser.maximumNestingDepth
        let markup = String(repeating: "{{a|", count: depth + 1) + "x" + String(repeating: "}}", count: depth + 1)
        #expect(throws: StretchParseError.nestingTooDeep(at(1, 4 * depth + 1))) {
            try parse(markup, mode)
        }
        let hostile = String(repeating: "{{a|", count: 100_000)
        #expect(throws: StretchParseError.nestingTooDeep(at(1, 4 * depth + 1))) {
            try parse(hostile, mode)
        }
    }
}

/// Chama `body` com toda cadeia de até `maxLength` símbolos de `alphabet`, inclusive a vazia.
private func forEachString(over alphabet: [String], maxLength: Int, _ body: (String) -> Void) {
    func extend(_ current: String, _ remaining: Int) {
        body(current)
        guard remaining > 0 else { return }
        for symbol in alphabet { extend(current + symbol, remaining - 1) }
    }
    extend("", maxLength)
}
