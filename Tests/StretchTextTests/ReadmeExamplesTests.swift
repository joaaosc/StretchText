import Testing
import StretchText

/// Os exemplos do README, para que continuem compilando e corretos.
@Suite("Exemplos do README")
struct ReadmeExamplesTests {
    let markdown = """
        # Notas

        O build falha em uma de cada cinco execuções. O motivo é um cache velho.

        Uma frase só.
        """

    @Test("Dobrar um texto existente")
    func foldExisting() throws {
        let segmentation = TextSegmenter.segment(markdown)
        let result = StretchFolder.foldWithFirstSentence(segmentation)
        #expect(result.document.collapsedText.contains("O build falha em uma de cada cinco execuções.\n"))
        #expect(result.document.expandedText == markdown)
        #expect(result.decisions.count == segmentation.segments.count)

        let choice = SentenceChoice(sentenceID: SentenceID(segment: 2, index: 1), source: .firstSentence)
        let folded = try StretchFolder.fold(segmentation, choices: [2: choice])
        #expect(folded.document.collapsedText.contains("O motivo é um cache velho."))
    }

    @Test("Ler, escrever, estado e validação")
    func markupAndState() throws {
        let document = try StretchParser.parse("O build {{falha.|falha em uma de cada cinco execuções.}}")
        let markup = StretchWriter.markup(for: document)
        #expect(try StretchParser.parse(markup) == document)

        var state = StretchState(document: document)
        let id = document.stretchIDs[0]
        #expect(state.toggle(id) == .opened)
        #expect(state.visibleText == "O build falha em uma de cada cinco execuções.")
        #expect(state.anchors(revealing: id)?.addedWords == ["em", "uma", "de", "cada", "cinco", "execuções"])

        #expect(StretchValidator.validate(document).isEmpty)
    }
}
