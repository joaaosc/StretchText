import Testing
@testable import StretchText

@Suite("Trocar a caixa de uma tarefa")
struct TaskToggleTests {
    /// O primeiro bloco do tipo pedido.
    static func segment(_ kind: Segment.Kind, in segmentation: Segmentation) throws -> Int {
        try #require(segmentation.segments.first { $0.kind == kind }).id
    }

    static func toggled(_ source: String) throws -> String? {
        let segmentation = TextSegmenter.segment(source)
        return segmentation.togglingTask(inSegment: try segment(.listItem, in: segmentation))
    }

    @Test("A caixa vazia vira marcada, e a marcada (x ou X) vira vazia", arguments: [
        ("- [ ] a", "- [x] a"),
        ("- [x] a", "- [ ] a"),
        ("- [X] a", "- [ ] a"),
        ("* [ ] a", "* [x] a"),
        ("+ [ ] a", "+ [x] a"),
        ("- [x]", "- [ ]"),
        ("- [ ]", "- [x]"),
        ("  - [ ] a", "  - [x] a"),
        ("-\t[ ] a", "-\t[x] a"),
        ("- [ ] a\n  continua - [ ] aqui", "- [x] a\n  continua - [ ] aqui"),
        ("- [ ] primeira\n- [ ] segunda", "- [x] primeira\n- [ ] segunda"),
    ])
    func toggles(source: String, expected: String) throws {
        #expect(try Self.toggled(source) == expected)
    }

    @Test("Tarefa aninhada com 2 ou 3 espaços")
    func nested() throws {
        for indent in ["  ", "   "] {
            let segmentation = TextSegmenter.segment("- pai\n\(indent)- [ ] filha\n\(indent)- [x] outra")
            let items = segmentation.segments.filter { $0.kind == .listItem }.map(\.id)
            #expect(items.count == 3)
            #expect(segmentation.togglingTask(inSegment: items[0]) == nil)
            #expect(segmentation.togglingTask(inSegment: items[1]) == "- pai\n\(indent)- [x] filha\n\(indent)- [x] outra")
            #expect(segmentation.togglingTask(inSegment: items[2]) == "- pai\n\(indent)- [ ] filha\n\(indent)- [ ] outra")
        }
    }

    @Test("Só o bloco pedido muda quando há várias tarefas")
    func onlyRequestedBlock() throws {
        let segmentation = TextSegmenter.segment("- [ ] a\n- [ ] b\n- [x] c")
        let items = segmentation.segments.filter { $0.kind == .listItem }.map(\.id)
        #expect(items.count == 3)
        #expect(segmentation.togglingTask(inSegment: items[1]) == "- [ ] a\n- [x] b\n- [x] c")
        #expect(segmentation.togglingTask(inSegment: items[2]) == "- [ ] a\n- [ ] b\n- [ ] c")
    }

    @Test("Não é tarefa, então devolve nil", arguments: [
        "- a",
        "1. [ ] a",
        "1) [x] a",
        "Um parágrafo [ ] com caixa",
        "# [ ] título",
        "```\n- [ ] a\n```",
        "    - [ ] a",
        "> - [ ] a",
        "| a | b |\n| - | - |\n| [ ] | x |",
        "- [ ]x",
        "- [] a",
        "- [y] a",
        "-[ ] a",
    ])
    func notATask(source: String) throws {
        let segmentation = TextSegmenter.segment(source)
        for segment in segmentation.segments {
            #expect(segmentation.togglingTask(inSegment: segment.id) == nil, "bloco \(segment.id): \(segment.kind)")
        }
    }

    @Test("Bloco que não existe devolve nil")
    func missingBlock() {
        let segmentation = TextSegmenter.segment("- [ ] a")
        #expect(segmentation.togglingTask(inSegment: -1) == nil)
        #expect(segmentation.togglingTask(inSegment: segmentation.segments.count) == nil)
        #expect(segmentation.togglingTask(inSegment: 1_000) == nil)
        #expect(TextSegmenter.segment("").togglingTask(inSegment: 0) == nil)
    }

    @Test("Acentos e emoji antes da tarefa não deslocam a troca (o deslocamento é em UTF-8)")
    func accentsBeforeTask() throws {
        let source = "Título é ção 👩‍👩‍👧\n\nParágrafo.\n\n- [ ] ação é útil 🎉\n- [x] café"
        let segmentation = TextSegmenter.segment(source)
        let items = segmentation.segments.filter { $0.kind == .listItem }.map(\.id)
        #expect(segmentation.togglingTask(inSegment: items[0]) == "Título é ção 👩‍👩‍👧\n\nParágrafo.\n\n- [x] ação é útil 🎉\n- [x] café")
        #expect(segmentation.togglingTask(inSegment: items[1]) == "Título é ção 👩‍👩‍👧\n\nParágrafo.\n\n- [ ] ação é útil 🎉\n- [ ] café")
    }

    @Test("Depois da troca, a estrutura é a mesma e só aquela tarefa muda")
    func structureStaysTheSame() throws {
        let source = """
            Introdução com acento. Segunda frase.

            - [ ] primeira
              continuação
              - [x] aninhada
            - item comum

            > - [ ] na citação

            ```
            - [ ] no código
            ```
            """
        let before = TextSegmenter.segment(source)
        let tasks = before.segments.filter { ReadingBlockTests.isTask($0) }.map(\.id)
        #expect(tasks.count == 2)
        for id in tasks {
            let after = TextSegmenter.segment(try #require(before.togglingTask(inSegment: id)))
            #expect(after.segments.map(\.kind) == before.segments.map(\.kind))
            #expect(after.segments.map(\.utf8Range) == before.segments.map(\.utf8Range))
            #expect(after.segments.map(\.sentences.count) == before.segments.map(\.sentences.count))
            #expect(Self.blocks(after).map(\.id) == Self.blocks(before).map(\.id))
            for (old, new) in zip(Self.blocks(before), Self.blocks(after)) {
                if old.id == id {
                    guard case .listItem(.task(let wasDone), let depth) = old.kind else {
                        Issue.record("bloco \(id) não era tarefa")
                        continue
                    }
                    #expect(new.kind == .listItem(marker: .task(isDone: !wasDone), depth: depth))
                    #expect(new.text == old.text)
                } else {
                    #expect(new == old)
                }
            }
        }
    }

    @Test("Trocar duas vezes volta ao original; com [X], volta como [x]")
    func toggleTwice() throws {
        for source in ["- [ ] a\n\nFim", "- [x] a\n\nFim"] {
            let first = TextSegmenter.segment(source)
            let once = try #require(first.togglingTask(inSegment: 0))
            #expect(once != source)
            #expect(TextSegmenter.segment(once).togglingTask(inSegment: 0) == source)
        }
        // O `X` maiúsculo não volta como estava: a segunda troca escreve `x`.
        let upper = TextSegmenter.segment("- [X] a")
        let off = try #require(upper.togglingTask(inSegment: 0))
        #expect(off == "- [ ] a")
        #expect(TextSegmenter.segment(off).togglingTask(inSegment: 0) == "- [x] a")
    }

    static func blocks(_ segmentation: Segmentation) -> [ReadingBlock] {
        segmentation.segments.compactMap { segment in
            guard segment.kind != .blank else { return nil }
            let content = ReadingBlock.content(of: segment)
            return ReadingBlock(id: segment.id, kind: content.kind, text: content.text)
        }
    }
}

extension ReadingBlockTests {
    /// Se o bloco é um item de tarefa, pela regra de desenho.
    static func isTask(_ segment: Segment) -> Bool {
        if case .listItem(.task, _) = ReadingBlock.content(of: segment).kind { true } else { false }
    }
}

extension TaskToggleTests {
    @Test("Com tab ou 4 colunas, a linha aninhada é continuação do pai: só a primeira linha tem caixa")
    func deepIndentIsContinuation() {
        for indent in ["    ", "\t"] {
            let segmentation = TextSegmenter.segment("- [ ] pai\n\(indent)- [ ] filha")
            #expect(segmentation.segments.filter { $0.kind == .listItem }.count == 1)
            #expect(segmentation.togglingTask(inSegment: 0) == "- [x] pai\n\(indent)- [ ] filha")
        }
    }
}
