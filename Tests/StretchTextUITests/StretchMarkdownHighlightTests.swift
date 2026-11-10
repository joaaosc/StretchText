import Foundation
import StretchText
import SwiftUI
import Testing

@testable import StretchTextUI

@Suite("Marca-texto, realce e âncora na leitura em Markdown")
@MainActor
struct StretchMarkdownHighlightTests {
    static let mark = Color.green
    static let found = Color.yellow
    static let current = Color.red

    static func style(mark: Color? = nil) -> StretchMarkdownStyle {
        StretchMarkdownStyle(markColor: mark, highlightColor: found, currentHighlightColor: current)
    }

    /// O que `MarkdownInline.attributed` devolvia na versão 1.0.2.
    static func legacy(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// Os trechos do texto que têm `color` de fundo, na ordem.
    static func painted(_ text: AttributedString, _ color: Color) -> [String] {
        text.runs.compactMap { run in
            run.backgroundColor == color ? String(text[run.range].characters) : nil
        }
    }

    static func hasBackground(_ text: AttributedString) -> Bool {
        text.runs.contains { $0.backgroundColor != nil }
    }

    // MARK: - Compatibilidade com a 1.0

    @Test("Sem markColor e sem realces, o resultado é idêntico ao da 1.0.2")
    func identicalToLegacy() {
        let samples = [
            "", "Sem marcação, com 3,14 e C:\\pasta.", "um **dois** _três_ `quatro` e [link](https://exemplo.com)",
            "veja ==isto== agora", "x == y e a === b", "`a==b==c` e ==d==", "==abre\n\nfecha==", "**aberto", "5 * 3 = 15",
            "a\nb  c", "\\*literal\\*",
        ]
        for sample in samples {
            #expect(MarkdownInline.attributed(sample) == Self.legacy(sample))
            #expect(MarkdownInline.attributed(sample, style: Self.style(), highlights: []) == Self.legacy(sample))
            #expect(MarkdownInline.attributed(sample, style: StretchMarkdownStyle(), highlights: []) == Self.legacy(sample))
        }
        #expect(StretchMarkdownStyle().markColor == nil)
    }

    @Test("Sem markColor, o == continua na tela e só o realce pinta")
    func literalMarkWithoutColor() {
        let text = MarkdownInline.attributed(
            "veja ==isto== agora", style: Self.style(),
            highlights: [
                ReadingHighlight(block: 0, range: 5..<9)
            ])
        #expect(String(text.characters) == "veja ==isto== agora")
        #expect(Self.painted(text, Self.found) == ["isto"])
        #expect(Self.painted(text, Self.mark).isEmpty)
    }

    // MARK: - Marca-texto

    @Test("Com markColor, o == vira fundo no trecho e sai do texto")
    func markColor() {
        let text = MarkdownInline.attributed("veja ==isto== agora e ==**aquilo**==", style: Self.style(mark: Self.mark), highlights: [])
        #expect(String(text.characters) == "veja isto agora e aquilo")
        #expect(Self.painted(text, Self.mark) == ["isto", "aquilo"])
    }

    @Test("Código em linha, == sem par e == com espaço ficam intactos")
    func markLeavesCodeAlone() {
        for sample in ["use `a==b==c` aqui", "só ==abre", "x == y", "==a\n\nb=="] {
            let text = MarkdownInline.attributed(sample, style: Self.style(mark: Self.mark), highlights: [])
            #expect(text == Self.legacy(sample), "\(sample)")
            #expect(!Self.hasBackground(text))
        }
        let mixed = MarkdownInline.attributed("==fora `a==b` dentro==", style: Self.style(mark: Self.mark), highlights: [])
        #expect(String(mixed.characters) == "fora a==b dentro")
        #expect(Self.painted(mixed, Self.mark) == ["fora ", "a==b", " dentro"])
        #expect(mixed.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    // MARK: - Realce

    @Test("Os intervalos pedidos ganham fundo de realce e o atual, a outra cor")
    func highlightColors() {
        let text = MarkdownInline.attributed(
            "um **dois** três quatro cinco",
            style: Self.style(),
            highlights: [
                ReadingHighlight(block: 1, range: 0..<2),
                ReadingHighlight(block: 1, range: 3..<7, isCurrent: true),
                ReadingHighlight(block: 1, range: 13..<19),
            ]
        )
        #expect(String(text.characters) == "um dois três quatro cinco")
        #expect(Self.painted(text, Self.found) == ["um", "quatro"])
        #expect(Self.painted(text, Self.current) == ["dois"])
    }

    @Test("Com markColor, o realce conta o texto sem os ==")
    func highlightCountsDisplayedText() {
        let text = MarkdownInline.attributed(
            "veja ==isto== agora",
            style: Self.style(mark: Self.mark),
            highlights: [ReadingHighlight(block: 0, range: 5..<15, isCurrent: true)]
        )
        #expect(String(text.characters) == "veja isto agora")
        #expect(Self.painted(text, Self.current) == ["isto agora"])
        // O realce é pintado depois do marca-texto e vence onde os dois se encontram.
        #expect(Self.painted(text, Self.mark).isEmpty)
    }

    @Test("Sem markColor, o realce que cobre um trecho marcado cobre também os ==")
    func highlightAcrossLiteralMark() {
        // Texto exibido: "a b c". Na tela, com os == literais: "a ==b== c".
        let cases: [(range: Range<Int>, painted: String)] = [
            (0..<5, "a ==b== c"),
            (2..<3, "b"),
            (3..<5, " c"),
            (0..<3, "a ==b"),
        ]
        for (range, painted) in cases {
            let text = MarkdownInline.attributed("a ==b== c", style: Self.style(), highlights: [ReadingHighlight(block: 0, range: range)])
            #expect(String(text.characters) == "a ==b== c")
            #expect(Self.painted(text, Self.found) == [painted], "\(range)")
        }
    }

    @Test("Intervalo vazio, negativo ou fora do texto é ignorado; o resto é pintado")
    func outOfRange() {
        let text = MarkdownInline.attributed(
            "abcdef",
            style: Self.style(),
            highlights: [
                ReadingHighlight(block: 0, range: 3..<3),
                ReadingHighlight(block: 0, range: -4..<2),
                ReadingHighlight(block: 0, range: 4..<99),
                ReadingHighlight(block: 0, range: 50..<60),
            ]
        )
        #expect(String(text.characters) == "abcdef")
        #expect(Self.painted(text, Self.found) == ["ab", "ef"])
    }

    @Test("Realces que se sobrepõem: o atual vence e a ordem de entrada não importa")
    func overlapping() {
        let text = MarkdownInline.attributed(
            "abcdefgh",
            style: Self.style(),
            highlights: [
                ReadingHighlight(block: 0, range: 4..<8),
                ReadingHighlight(block: 0, range: 2..<6, isCurrent: true),
                ReadingHighlight(block: 0, range: 0..<3),
            ]
        )
        #expect(Self.painted(text, Self.current) == ["cdef"])
        #expect(Self.painted(text, Self.found) == ["ab", "gh"])
    }

    @Test("Código e tabela: texto literal, só com os realces")
    func verbatim() {
        let text = MarkdownInline.attributed(
            verbatim: "let a = **b** ==c==",
            style: Self.style(mark: Self.mark),
            highlights: [ReadingHighlight(block: 0, range: 14..<17)]
        )
        #expect(String(text.characters) == "let a = **b** ==c==")
        #expect(Self.painted(text, Self.found) == ["==c"])
        #expect(Self.painted(text, Self.mark).isEmpty)
    }

    @Test("Os realces do ambiente se agrupam por bloco")
    func environmentGroups() {
        let all = MarkdownHighlights([
            ReadingHighlight(block: 2, range: 0..<1),
            ReadingHighlight(block: 5, range: 1..<2),
            ReadingHighlight(block: 2, range: 3..<4, isCurrent: true),
        ])
        #expect(all[2].map(\.range) == [0..<1, 3..<4])
        #expect(all[5].count == 1)
        #expect(all[0].isEmpty)
        #expect(EnvironmentValues().stretchMarkdownHighlights == MarkdownHighlights())
    }

    // MARK: - Âncora e desenho

    @Test("A âncora é o índice do bloco")
    func anchor() {
        #expect(ReadingBlockAnchor(3) == ReadingBlockAnchor(3))
        #expect(ReadingBlockAnchor(3) != ReadingBlockAnchor(4))
        #expect(Set([ReadingBlockAnchor(1), ReadingBlockAnchor(1), ReadingBlockAnchor(2)]).count == 2)
        #expect(ReadingBlockAnchor(7).block == 7)
    }

    static let result = StretchFolder.foldWithFirstSentence(
        TextSegmenter.segment(
            """
            # Título com ==marca==

            Primeira ==frase==. Segunda frase.

            - item ==um==
            - [ ] tarefa

            > citação ==aqui==

            ```
            código ==literal==
            ```
            """))

    static func evaluate(_ view: some View) {
        let renderer = ImageRenderer(content: view.frame(width: 320, height: 480))
        _ = renderer.cgImage
    }

    @Test("A view desenha com realces, com cores novas, interativa e só leitura")
    func rendersWithHighlights() {
        let state = StretchState(document: Self.result.document)
        let blocks = ReadingBlock.blocks(for: Self.result, state: state)
        let highlights = ReadingSearch.matches(of: "frase", in: blocks).map { ReadingHighlight(block: $0.block, range: $0.range) }
        #expect(highlights.count == 1)
        let style = StretchMarkdownStyle(markColor: .green)
        Self.evaluate(
            StretchMarkdownView(result: Self.result, state: .constant(state))
                .stretchMarkdownStyle(style)
                .stretchMarkdownHighlights(highlights)
        )
        Self.evaluate(
            StretchMarkdownView(result: Self.result, state: state)
                .stretchMarkdownHighlights(
                    ReadingSearch.matches(of: "e", in: blocks).map {
                        ReadingHighlight(block: $0.block, range: $0.range, isCurrent: $0.block == 0)
                    })
        )
    }

    @Test("As linhas de lista e de citação desenham com realce e marca-texto")
    func listAndQuoteRender() {
        let style = Self.style(mark: Self.mark)
        Self.evaluate(
            MarkdownListItemView(
                id: 1, text: "fazer ==isto==", marker: .task(isDone: false), depth: 0, action: {},
                highlights: [ReadingHighlight(block: 1, range: 0..<5)]
            ).stretchMarkdownStyle(style)
        )
        Self.evaluate(
            MarkdownQuoteView(text: "citação ==aqui==", highlights: [ReadingHighlight(block: 2, range: 0..<3)])
                .stretchMarkdownStyle(style)
        )
    }

    /// Cópia do exemplo do README, para que continue compilando.
    static func readmeExample(result: FoldResult, state: Binding<StretchState>, termo: String, atual: Int) -> some View {
        let blocos = ReadingBlock.blocks(for: result, state: state.wrappedValue)
        let achados = ReadingSearch.matches(of: termo, in: blocos)
        return ScrollViewReader { proxy in
            ScrollView {
                StretchMarkdownView(result: result, state: state)
                    .stretchMarkdownStyle(StretchMarkdownStyle(markColor: .yellow.opacity(0.4)))
                    .stretchMarkdownHighlights(
                        achados.enumerated().map { posicao, achado in
                            ReadingHighlight(block: achado.block, range: achado.range, isCurrent: posicao == atual)
                        })
            }
            .onChange(of: atual) {
                proxy.scrollTo(ReadingBlockAnchor(achados[atual].block), anchor: .top)
            }
        }
    }

    @Test("O exemplo do README compila e renderiza")
    func readmeExampleDraws() {
        let state = StretchState(document: Self.result.document)
        Self.evaluate(Self.readmeExample(result: Self.result, state: .constant(state), termo: "frase", atual: 0))
    }

    @Test("O texto que a tela mostra é o plainText do bloco, em todo tipo de bloco")
    func screenMatchesPlainText() {
        let style = Self.style(mark: Self.mark)
        for block in ReadingBlock.blocks(for: Self.result, state: StretchState(document: Self.result.document)) {
            switch block.kind {
            case .paragraph, .heading, .listItem, .blockQuote:
                #expect(String(MarkdownInline.attributed(block.text, style: style, highlights: []).characters) == block.plainText)
            case .codeBlock, .table, .thematicBreak, .image:
                #expect(block.plainText == block.text)
            }
        }
    }
}
