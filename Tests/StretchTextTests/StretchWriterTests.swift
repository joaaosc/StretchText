import Testing
@testable import StretchText

private func stretch(
    _ short: [InlineNode],
    _ long: [StretchNode],
    _ progress: Stretch.Progress = .complete
) -> StretchNode {
    .stretch(Stretch(short: short, long: long, progress: progress))
}

/// Toda cadeia de até `maxLength` símbolos de `alphabet`, inclusive a vazia.
private func allStrings(over alphabet: [String], maxLength: Int) -> [String] {
    var result = [""]
    var frontier = [""]
    for _ in 0..<maxLength {
        frontier = frontier.flatMap { prefix in alphabet.map { prefix + $0 } }
        result += frontier
    }
    return result
}

@Suite("Escritor de marcação")
struct StretchWriterTests {
    @Test("Escreve trecho com curta, separador e longa")
    func simpleStretch() {
        let document = StretchDocument(nodes: [
            .text("Antes "),
            stretch([.text("curta")], [.text("curta e longa")]),
            .text(" depois"),
        ])
        #expect(StretchWriter.markup(for: document) == "Antes {{curta|curta e longa}} depois")
    }

    @Test("Escapa os seis especiais em todo texto, em todos os níveis")
    func escapesEverySpecial() {
        let specials = #"\{}|`~"#
        let document = StretchDocument(nodes: [
            .text(specials),
            stretch([.text(specials)], [.text(specials), stretch([.text("x")], [.text(specials)])]),
        ])
        let escaped = #"\\\{\}\|\`\~"#
        #expect(StretchWriter.markup(for: document) == escaped + "{{" + escaped + "|" + escaped + "{{x|" + escaped + "}}}}")
    }

    @Test("Código sai como está, sem escape")
    func codeIsRaw() {
        let document = StretchDocument(nodes: [
            .code("`a{{b|c}}`"),
            stretch([.code("`|`")], [.code("`|`"), .text(" mais")]),
        ])
        #expect(StretchWriter.markup(for: document) == "`a{{b|c}}`{{`|`|`|` mais}}")
    }

    @Test("Trecho incompleto sai sem o que ainda não chegou")
    func incompleteStretches() throws {
        let receivingLong = StretchDocument(nodes: [
            .text("a "),
            stretch([.text("b")], [.text("b c "), stretch([.text("d")], [], .receivingShort)], .receivingLong),
        ])
        #expect(StretchWriter.markup(for: receivingLong) == "a {{b|b c {{d")
        #expect(try StretchParser.parse(StretchWriter.markup(for: receivingLong), mode: .streaming) == receivingLong)
    }

    @Test("Ida e volta de documentos montados à mão", arguments: [
        StretchDocument(nodes: []),
        StretchDocument(nodes: [.text(#"C:\pasta\arquivo {x} a|b `c` ~d ``"#)]),
        StretchDocument(nodes: [.text("Linha\n```\nnão é cerca\n```\n~~~\n")]),
        StretchDocument(nodes: [
            .text("Use "), .code("`x|y`"), .text(" e "),
            stretch([.text("o "), .code("``a`b``")], [.text("o "), .code("``a`b``"), .text(" com |barra| e {chaves}")]),
        ]),
        StretchDocument(nodes: [
            .text("Antes\n"), .code("```swift\nlet a = \"{{b|c}}\"\n```"), .text("\nDepois "),
            stretch([.text("A")], [.text("A, "), stretch([.text("B")], [.text("B e "), stretch([.text("C")], [.text("C!")])])]),
        ]),
        StretchDocument(nodes: [stretch([.text("Ação é")], [.text("Ontem, a ação é ótima — “sim”.")])]),
        StretchDocument(nodes: [stretch([], [])]),
    ])
    func roundTripBuiltDocuments(document: StretchDocument) throws {
        #expect(try StretchParser.parse(StretchWriter.markup(for: document)) == document)
    }

    @Test("Ida e volta de documentos incompletos no modo .streaming", arguments: [
        StretchDocument(nodes: [.text("x "), stretch([.text("a|b")], [], .receivingShort)]),
        StretchDocument(nodes: [stretch([.text("a")], [.text("a {b}")], .receivingLong)]),
        StretchDocument(nodes: [stretch([.text("a")], [.text("a "), stretch([.text("b")], [.text("b c")])], .receivingLong)]),
    ])
    func roundTripIncomplete(document: StretchDocument) throws {
        #expect(try StretchParser.parse(StretchWriter.markup(for: document), mode: .streaming) == document)
    }

    @Test("Texto qualquer nunca abre código nem trecho ao ser lido de volta")
    func textNeverOpensSyntax() throws {
        let alphabet = ["{", "}", "|", "\\", "`", "~", "a", "\n", " "]
        var failures: [String] = []
        for text in allStrings(over: alphabet, maxLength: 5) {
            let document = StretchDocument(nodes: [.text(text)])
            let reparsed = try? StretchParser.parse(StretchWriter.markup(for: document))
            if reparsed != document { failures.append(text.debugDescription) }
        }
        #expect(failures.isEmpty, "primeiras falhas: \(failures.prefix(5))")
    }

    @Test("Documento lido pelo parser volta igual depois de escrito")
    func parserOutputIsFixpoint() {
        let alphabet = ["{{", "|", "}}", "\\", "`", "~~~", "a", "\n"]
        var failures: [String] = []
        for mode in [StretchParser.Mode.complete, .streaming] {
            for markup in allStrings(over: alphabet, maxLength: 5) {
                guard let document = try? StretchParser.parse(markup, mode: mode) else { continue }
                let reparsed = try? StretchParser.parse(StretchWriter.markup(for: document), mode: mode)
                if reparsed != document { failures.append("\(mode) \(markup.debugDescription)") }
            }
        }
        #expect(failures.isEmpty, "primeiras falhas: \(failures.prefix(5))")
    }
}
