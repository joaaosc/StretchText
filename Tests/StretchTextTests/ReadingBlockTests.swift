import Testing
@testable import StretchText

@Suite("Blocos de leitura")
struct ReadingBlockTests {
    static func blocks(_ source: String, opening ids: [String] = []) throws -> [ReadingBlock] {
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source))
        var state = StretchState(document: result.document)
        for id in ids {
            #expect(state.toggle(try #require(StretchID(id))) == .opened)
        }
        return ReadingBlock.blocks(for: result, state: state)
    }

    @Test("Parágrafo dobrado mostra a curta fechado e a longa aberto, no mesmo bloco")
    func stretchParagraph() throws {
        let source = "Primeira frase. Segunda frase.\n\nUma frase só."
        let id = try #require(StretchID("0"))
        #expect(try Self.blocks(source) == [
            ReadingBlock(id: 0, kind: .paragraph, text: "Primeira frase.", stretch: id, isOpen: false),
            ReadingBlock(id: 2, kind: .paragraph, text: "Uma frase só."),
        ])
        #expect(try Self.blocks(source, opening: ["0"]).first
            == ReadingBlock(id: 0, kind: .paragraph, text: "Primeira frase. Segunda frase.", stretch: id, isOpen: true))
    }

    @Test("O texto do trecho é o mesmo do estado de leitura")
    func matchesVisibleText() throws {
        let source = "Um dois. Três quatro.\n\nCinco seis. Sete oito.\nNove dez.\n\nOnze doze. Treze."
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source))
        var state = StretchState(document: result.document)
        state.toggle(try #require(StretchID("1")))
        let blocks = ReadingBlock.blocks(for: result, state: state)
        #expect(blocks.count == 3)
        for block in blocks {
            let id = try #require(block.stretch)
            #expect(block.text == state.visibleText(of: id))
            #expect(block.isOpen == state.isOpen(id))
        }
    }

    @Test("Documento sem trechos: os blocos ficam inteiros e sem `.blank`")
    func noStretches() throws {
        #expect(try Self.blocks("Uma frase.\n\n\nOutra frase.\n") == [
            ReadingBlock(id: 0, kind: .paragraph, text: "Uma frase."),
            ReadingBlock(id: 2, kind: .paragraph, text: "Outra frase."),
        ])
        #expect(try Self.blocks("").isEmpty)
    }

    @Test(
        "Títulos perdem a marcação e guardam o nível",
        arguments: [
            ("# Título", 1, "Título"),
            ("###   Três   ", 3, "Três"),
            ("## Fecha ##", 2, "Fecha"),
            ("## C# #", 2, "C#"),
            ("#", 1, ""),
            ("Sublinhado\n===", 1, "Sublinhado"),
            ("Duas\nlinhas\n---", 2, "Duas\nlinhas"),
        ])
    func headings(source: String, level: Int, text: String) throws {
        #expect(try Self.blocks(source) == [ReadingBlock(id: 0, kind: .heading(level: level), text: text)])
    }

    @Test(
        "Itens de lista perdem o marcador e guardam o tipo e a profundidade",
        arguments: [
            ("- Item", ReadingBlock.ListMarker.bullet, 0, "Item"),
            ("* Item", .bullet, 0, "Item"),
            ("  + Sub", .bullet, 1, "Sub"),
            ("3. Terceiro", .ordered(3), 0, "Terceiro"),
            ("1) Um", .ordered(1), 0, "Um"),
            ("- [ ] Fazer", .task(isDone: false), 0, "Fazer"),
            ("- [x] Feito", .task(isDone: true), 0, "Feito"),
            ("- [X]", .task(isDone: true), 0, ""),
            ("- [y] Não é tarefa", .bullet, 0, "[y] Não é tarefa"),
            ("- Item\ncontinua", .bullet, 0, "Item\ncontinua"),
        ])
    func listItems(source: String, marker: ReadingBlock.ListMarker, depth: Int, text: String) throws {
        #expect(try Self.blocks(source) == [ReadingBlock(id: 0, kind: .listItem(marker: marker, depth: depth), text: text)])
    }

    @Test("Continuação indentada de um item fica sem marcador, no nível do item")
    func itemContinuation() throws {
        let blocks = try Self.blocks("- Item\n\n  Continua aqui.")
        #expect(blocks.last == ReadingBlock(id: 2, kind: .listItem(marker: nil, depth: 0), text: "Continua aqui."))
    }

    @Test("Citação perde o `>` e um espaço de cada linha")
    func quote() throws {
        #expect(try Self.blocks("> Uma\n>Duas\n  >  Três") == [
            ReadingBlock(id: 0, kind: .blockQuote, text: "Uma\nDuas\n Três"),
        ])
    }

    @Test("Código cercado com linha em branco dentro fica num bloco só, sem as cercas")
    func fencedCode() throws {
        let source = "```swift\nlet a = 1\n\nlet b = 2\n```\n\nDepois."
        #expect(try Self.blocks(source) == [
            ReadingBlock(id: 0, kind: .codeBlock(language: "swift"), text: "let a = 1\n\nlet b = 2"),
            ReadingBlock(id: 2, kind: .paragraph, text: "Depois."),
        ])
    }

    @Test("Cerca sem fechamento vai até o fim; cerca de tis aceita qualquer texto")
    func unclosedAndTildeFences() throws {
        #expect(try Self.blocks("~~~ texto livre\nx\n") == [ReadingBlock(id: 0, kind: .codeBlock(language: "texto"), text: "x")])
        #expect(try Self.blocks("```\n") == [ReadingBlock(id: 0, kind: .codeBlock(language: nil), text: "")])
    }

    @Test("Código indentado perde até 4 colunas de cada linha")
    func indentedCode() throws {
        #expect(try Self.blocks("    let a = 1\n\tlet b = 2\n      dentro") == [
            ReadingBlock(id: 0, kind: .codeBlock(language: nil), text: "let a = 1\nlet b = 2\n  dentro"),
        ])
    }

    @Test("Tabela fica como está; separador temático fica sem texto")
    func tableAndBreak() throws {
        #expect(try Self.blocks("| a | b |\n|---|---|\n| 1 | 2 |\n\n---") == [
            ReadingBlock(id: 0, kind: .table, text: "| a | b |\n|---|---|\n| 1 | 2 |"),
            ReadingBlock(id: 2, kind: .thematicBreak, text: ""),
        ])
    }

    @Test("Imagem sozinha vira um bloco .image, com o texto alternativo como texto")
    func image() throws {
        #expect(try Self.blocks("![Foto da obra](obra.png)") == [
            ReadingBlock(id: 0, kind: .image(MarkdownImage(alt: "Foto da obra", source: "obra.png")), text: "Foto da obra"),
        ])
    }

    @Test(
        "Imagem guarda texto alternativo, origem e título como em MarkdownImage.parse",
        arguments: [
            "![Foto](obra.png)",
            "![Foto](obra.png \"Sala de estar\")",
            "  ![Foto](<minha obra.png>)  ",
            "![](obra.png)",
        ])
    func imageMatchesParse(line: String) throws {
        let expected = try #require(MarkdownImage.parse(line))
        #expect(try Self.blocks(line) == [ReadingBlock(id: 0, kind: .image(expected), text: expected.alt)])
    }

    @Test("Imagem entre parágrafos não dobra, mesmo com o texto alternativo de duas frases")
    func imageBetweenParagraphs() throws {
        let source = "Primeira frase. Segunda frase.\n\n![Uma frase. Duas frases.](a.png)\n\nOutra. Mais uma."
        let blocks = try Self.blocks(source)
        #expect(blocks.map(\.id) == [0, 2, 4])
        #expect(blocks[1] == ReadingBlock(
            id: 2,
            kind: .image(MarkdownImage(alt: "Uma frase. Duas frases.", source: "a.png")),
            text: "Uma frase. Duas frases."
        ))
        #expect(blocks[0].stretch != nil)
        #expect(blocks[1].stretch == nil && !blocks[1].isOpen)
        #expect(blocks[2].stretch != nil)
        // Abrir os trechos vizinhos não muda a imagem.
        #expect(try Self.blocks(source, opening: ["0", "1"])[1] == blocks[1])
    }

    @Test("Imagem no meio do texto continua parágrafo, com a marcação no texto")
    func imageInsideText() throws {
        #expect(try Self.blocks("Veja ![Foto](a.png) agora.") == [
            ReadingBlock(id: 0, kind: .paragraph, text: "Veja ![Foto](a.png) agora."),
        ])
    }

    @Test("Imagem dentro de cerca de código fica no código")
    func imageInsideFence() throws {
        #expect(try Self.blocks("```\n![Foto](a.png)\n```") == [
            ReadingBlock(id: 0, kind: .codeBlock(language: nil), text: "![Foto](a.png)"),
        ])
    }

    @Test("Segmento .image montado à mão que não é imagem aparece como parágrafo")
    func handMadeImageSegment() {
        let text = "isto não é imagem"
        let segment = Segment(id: 0, kind: .image, text: text, utf8Range: 0..<text.utf8.count, sentences: [])
        let content = ReadingBlock.content(of: segment)
        #expect(content.kind == .paragraph)
        #expect(content.text == text)
    }

    @Test("CRLF: as linhas são separadas do mesmo jeito")
    func crlf() throws {
        #expect(try Self.blocks("> Uma\r\n> Duas\r\n") == [ReadingBlock(id: 0, kind: .blockQuote, text: "Uma\nDuas")])
    }

    @Test("Trecho que não existe no estado aparece inteiro")
    func staleState() throws {
        let source = "Um dois. Três quatro."
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(source))
        #expect(result.document.stretchIDs.count == 1)
        let other = StretchState(document: StretchDocument(nodes: [.text(source)]))
        #expect(ReadingBlock.blocks(for: result, state: other) == [ReadingBlock(id: 0, kind: .paragraph, text: source)])
    }
}
