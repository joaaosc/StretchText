import Testing
@testable import StretchText

@Suite("Montagem dos trechos")
struct StretchFolderTests {
    /// Dois parágrafos dobráveis, um de uma frase, um sem frase, um título,
    /// um item de lista e os espaços entre eles.
    static let sample = """
    Primeira frase. Segunda frase. Terceira frase.

    # Título

    Só uma frase.

    ...

    - item um. item dois.

    Outro parágrafo aqui. Com duas frases.

    """

    static let sampleSegmentation = TextSegmenter.segment(sample)

    /// Posição do bloco de cada tipo na amostra (conferida no primeiro teste).
    enum Index {
        static let firstParagraph = 0
        static let heading = 2
        static let single = 4
        static let noSentence = 6
        static let listItem = 8
        static let lastParagraph = 10
    }

    // MARK: - Linha de base

    @Test("A amostra tem os blocos esperados")
    func sampleLayout() {
        let kinds = Self.sampleSegmentation.segments.map(\.kind)
        #expect(kinds == [
            .paragraph, .blank, .heading, .blank, .paragraph, .blank,
            .paragraph, .blank, .listItem, .blank, .paragraph, .blank,
        ])
        let sentenceCounts = Self.sampleSegmentation.segments.map(\.sentences.count)
        #expect(sentenceCounts == [3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 0])
    }

    @Test("A linha de base dobra pela primeira frase e registra cada decisão")
    func firstSentenceBaseline() throws {
        let result = StretchFolder.foldWithFirstSentence(Self.sampleSegmentation)
        let segments = Self.sampleSegmentation.segments

        #expect(result.segmentation == Self.sampleSegmentation)
        #expect(result.decisions.count == segments.count)
        #expect(result.decisions.map(\.segment) == Array(segments.indices))

        let first = SentenceChoice(sentenceID: SentenceID(segment: 0, index: 0), source: .firstSentence)
        let last = SentenceChoice(sentenceID: SentenceID(segment: 10, index: 0), source: .firstSentence)
        #expect(result.decisions == [
            .folded(segment: 0, stretch: try #require(StretchID("0")), choice: first),
            .unchanged(segment: 1, reason: .ineligibleKind(.blank)),
            .unchanged(segment: 2, reason: .ineligibleKind(.heading)),
            .unchanged(segment: 3, reason: .ineligibleKind(.blank)),
            .unchanged(segment: 4, reason: .singleSentence),
            .unchanged(segment: 5, reason: .ineligibleKind(.blank)),
            .unchanged(segment: 6, reason: .noSentence),
            .unchanged(segment: 7, reason: .ineligibleKind(.blank)),
            .unchanged(segment: 8, reason: .ineligibleKind(.listItem)),
            .unchanged(segment: 9, reason: .ineligibleKind(.blank)),
            .folded(segment: 10, stretch: try #require(StretchID("1")), choice: last),
            .unchanged(segment: 11, reason: .ineligibleKind(.blank)),
        ])

        #expect(result.document.expandedText == Self.sample)
        #expect(result.document.collapsedText == """
        Primeira frase.

        # Título

        Só uma frase.

        ...

        - item um. item dois.

        Outro parágrafo aqui.

        """)
    }

    @Test("Cada trecho tem a frase como curta e o bloco literal como longa")
    func stretchContents() throws {
        let result = StretchFolder.foldWithFirstSentence(Self.sampleSegmentation)
        let stretches = result.document.stretchIDs.compactMap { result.document.stretch(at: $0) }
        #expect(stretches == [
            Stretch(
                short: [.text("Primeira frase.")],
                long: [.text("Primeira frase. Segunda frase. Terceira frase.")]
            ),
            Stretch(
                short: [.text("Outro parágrafo aqui.")],
                long: [.text("Outro parágrafo aqui. Com duas frases.")]
            ),
        ])
        #expect(stretches.allSatisfy { $0.isComplete })
    }

    @Test("Cada motivo de .unchanged aparece")
    func everyUnchangedReason() throws {
        let result = try StretchFolder.fold(Self.sampleSegmentation, choices: [:])
        let reasons = result.decisions.compactMap { decision -> UnchangedReason? in
            if case .unchanged(_, let reason) = decision { reason } else { nil }
        }
        #expect(reasons.contains(.ineligibleKind(.heading)))
        #expect(reasons.contains(.ineligibleKind(.listItem)))
        #expect(reasons.contains(.ineligibleKind(.blank)))
        #expect(reasons.contains(.noSentence))
        #expect(reasons.contains(.singleSentence))
        #expect(reasons.contains(.noChoice))
        #expect(result.decisions[Index.firstParagraph] == .unchanged(segment: 0, reason: .noChoice))
        #expect(result.decisions[Index.lastParagraph] == .unchanged(segment: 10, reason: .noChoice))
    }

    @Test("Sem escolhas nada dobra e o texto sai igual")
    func noChoicesLeavesTextAlone() throws {
        let result = try StretchFolder.fold(Self.sampleSegmentation, choices: [:])
        #expect(result.document.stretchIDs.isEmpty)
        #expect(result.document.collapsedText == Self.sample)
        #expect(result.document.expandedText == Self.sample)
    }

    @Test("Os blocos que não dobram viram um único texto contíguo")
    func unchangedBlocksMergeIntoText() throws {
        let segmentation = TextSegmenter.segment("# T\n\nSó um.\n")
        let result = StretchFolder.foldWithFirstSentence(segmentation)
        #expect(result.document.nodes == [.text("# T\n\nSó um.\n")])
    }

    // MARK: - Escolha de frases

    @Test("Escolha de uma frase do meio vira a forma curta")
    func middleSentenceChoice() throws {
        let paragraph = Self.sampleSegmentation.segments[Index.firstParagraph]
        let middle = paragraph.sentences[1]
        let choice = SentenceChoice(sentenceID: middle.id, source: .firstSentence)
        let result = try StretchFolder.fold(Self.sampleSegmentation, choices: [Index.firstParagraph: choice])

        #expect(result.decisions[Index.firstParagraph] == .folded(
            segment: 0, stretch: try #require(StretchID("0")), choice: choice
        ))
        #expect(result.document.stretch(at: try #require(StretchID("0")))?.shortText == "Segunda frase.")
        // O outro parágrafo dobrável ficou sem escolha.
        #expect(result.decisions[Index.lastParagraph] == .unchanged(segment: 10, reason: .noChoice))
        #expect(result.document.stretchIDs.count == 1)
        #expect(result.document.expandedText == Self.sample)
    }

    @Test("Os IDs de primeiro nível seguem a ordem dos trechos, não a do dicionário")
    func stretchIDsFollowDocumentOrder() throws {
        let segments = Self.sampleSegmentation.segments
        let choices: [Int: SentenceChoice] = [
            Index.lastParagraph: SentenceChoice(sentenceID: segments[Index.lastParagraph].sentences[1].id, source: .firstSentence),
            Index.firstParagraph: SentenceChoice(sentenceID: segments[Index.firstParagraph].sentences[2].id, source: .firstSentence),
        ]
        let result = try StretchFolder.fold(Self.sampleSegmentation, choices: choices)
        let folded = result.decisions.compactMap { decision -> (Int, StretchID)? in
            if case .folded(let segment, let stretch, _) = decision { (segment, stretch) } else { nil }
        }
        #expect(folded.map(\.0) == [Index.firstParagraph, Index.lastParagraph])
        #expect(folded.map(\.1.description) == ["0", "1"])
        #expect(result.document.stretchIDs.map(\.description) == ["0", "1"])
        #expect(result.document.stretch(at: folded[0].1)?.shortText == "Terceira frase.")
        #expect(result.document.stretch(at: folded[1].1)?.shortText == "Com duas frases.")
    }

    // MARK: - Erros

    @Test("Escolha para bloco inexistente lança .unknownSegment", arguments: [-1, 12, 99])
    func unknownSegment(_ index: Int) {
        let choice = SentenceChoice(sentenceID: SentenceID(segment: index, index: 0), source: .firstSentence)
        #expect(throws: FoldError.unknownSegment(index)) {
            try StretchFolder.fold(Self.sampleSegmentation, choices: [index: choice])
        }
    }

    @Test(
        "Escolha para bloco que não dobra lança .segmentNotFoldable",
        arguments: [
            Index.heading,      // título
            Index.single,       // uma frase
            Index.noSentence,   // nenhuma frase
            Index.listItem,     // item de lista
            1,                  // espaço
        ]
    )
    func segmentNotFoldable(_ index: Int) {
        let choice = SentenceChoice(sentenceID: SentenceID(segment: index, index: 0), source: .firstSentence)
        #expect(throws: FoldError.segmentNotFoldable(index)) {
            try StretchFolder.fold(Self.sampleSegmentation, choices: [index: choice])
        }
    }

    @Test("Frase de outro bloco ou inexistente lança .sentenceNotInSegment")
    func sentenceNotInSegment() {
        let otherBlock = SentenceID(segment: Index.lastParagraph, index: 0)
        let missingIndex = SentenceID(segment: Index.firstParagraph, index: 3)
        let negativeIndex = SentenceID(segment: Index.firstParagraph, index: -1)
        for id in [otherBlock, missingIndex, negativeIndex] {
            let choice = SentenceChoice(sentenceID: id, source: .firstSentence)
            #expect(throws: FoldError.sentenceNotInSegment(id, segment: Index.firstParagraph)) {
                try StretchFolder.fold(Self.sampleSegmentation, choices: [Index.firstParagraph: choice])
            }
        }
    }

    @Test("Todas as escolhas são conferidas em ordem crescente de bloco antes de montar")
    func validationOrder() {
        let valid = SentenceChoice(sentenceID: SentenceID(segment: 0, index: 1), source: .firstSentence)
        let unknown = SentenceChoice(sentenceID: SentenceID(segment: 99, index: 0), source: .firstSentence)
        let notFoldable = SentenceChoice(sentenceID: SentenceID(segment: 2, index: 0), source: .firstSentence)
        let wrongSentence = SentenceChoice(sentenceID: SentenceID(segment: 4, index: 0), source: .firstSentence)

        // O menor índice com problema decide o erro, mesmo com um bloco válido antes.
        #expect(throws: FoldError.segmentNotFoldable(2)) {
            try StretchFolder.fold(Self.sampleSegmentation, choices: [0: valid, 99: unknown, 2: notFoldable])
        }
        #expect(throws: FoldError.sentenceNotInSegment(wrongSentence.sentenceID, segment: 0)) {
            try StretchFolder.fold(Self.sampleSegmentation, choices: [10: wrongSentence, 0: wrongSentence])
        }
        #expect(throws: FoldError.unknownSegment(99)) {
            try StretchFolder.fold(Self.sampleSegmentation, choices: [0: valid, 99: unknown])
        }
    }

    // MARK: - shortForm

    @Test("A forma curta troca sequências com quebra de linha por um espaço", arguments: [
        ("sem quebras", "sem quebras"),
        ("", ""),
        ("a\nb", "a b"),
        ("a\r\nb", "a b"),
        ("a\rb", "a b"),
        ("a \n b", "a b"),
        ("a  \r\n  b", "a b"),
        ("a\n\n\nb", "a b"),
        ("a\nb\nc", "a b c"),
        ("a \u{2028} b", "a b"),
        ("a  b", "a  b"),
        ("a\tb", "a\tb"),
        ("a \t b", "a \t b"),
        ("um\n\tdois   três", "um dois   três"),
        ("Linha um\ncontinua aqui.", "Linha um continua aqui."),
        (" \n x", " x"),
        ("x \n", "x "),
    ])
    func shortForm(_ input: String, _ expected: String) {
        #expect(StretchFolder.shortForm(of: input) == expected)
    }

    @Test("A forma curta não altera pontuação, código nem acentos")
    func shortFormKeepsEverythingElse() {
        let text = "Veja `a.\nb` aqui, com “aspas” e açúcar — 😀!"
        #expect(StretchFolder.shortForm(of: text) == "Veja `a. b` aqui, com “aspas” e açúcar — 😀!")
    }

    @Test("Frase em várias linhas: curta numa linha, longa literal")
    func multilineSentence() throws {
        let source = "Esta frase\r\n   continua na linha de baixo. Outra frase.\r\n"
        let segmentation = TextSegmenter.segment(source)
        let result = StretchFolder.foldWithFirstSentence(segmentation)
        let id = try #require(StretchID("0"))
        let stretch = try #require(result.document.stretch(at: id))

        #expect(stretch.short == [.text("Esta frase continua na linha de baixo.")])
        #expect(stretch.long == [.text("Esta frase\r\n   continua na linha de baixo. Outra frase.")])
        #expect(result.document.collapsedText == "Esta frase continua na linha de baixo.\r\n")
        #expect(result.document.expandedText == source)
    }

    // MARK: - FirstSentencePicker

    @Test("O seletor devolve a primeira frase de bloco dobrável")
    func pickerFoldable() throws {
        let segment = Self.sampleSegmentation.segments[Index.firstParagraph]
        let choice = try #require(FirstSentencePicker().choose(in: segment))
        #expect(choice == SentenceChoice(sentenceID: SentenceID(segment: 0, index: 0), source: .firstSentence))
        #expect(choice.sentenceID == segment.sentences[0].id)
    }

    @Test("O seletor devolve nil para os demais blocos")
    func pickerNotFoldable() {
        let picker = FirstSentencePicker()
        for segment in Self.sampleSegmentation.segments where !segment.isFoldable {
            #expect(picker.choose(in: segment) == nil, "bloco \(segment.id) (\(segment.kind))")
        }
        let folded = Self.sampleSegmentation.segments.filter(\.isFoldable).map(\.id)
        #expect(folded == [Index.firstParagraph, Index.lastParagraph])
    }

    @Test("Escolhas do seletor passam pela validação de fold")
    func pickerChoicesAreValid() throws {
        let picker = FirstSentencePicker()
        var choices: [Int: SentenceChoice] = [:]
        for segment in Self.sampleSegmentation.segments {
            if let choice = picker.choose(in: segment) { choices[segment.id] = choice }
        }
        let viaFold = try StretchFolder.fold(Self.sampleSegmentation, choices: choices)
        #expect(viaFold == StretchFolder.foldWithFirstSentence(Self.sampleSegmentation))
    }

    // MARK: - Invariantes em todas as entradas

    @Test("O núcleo nunca altera o texto expandido", arguments: SegmentationFixtures.partitionInputs)
    func expandedTextEqualsSource(_ source: String) throws {
        let segmentation = TextSegmenter.segment(source)
        let baseline = StretchFolder.foldWithFirstSentence(segmentation)
        let noChoices = try StretchFolder.fold(segmentation, choices: [:])

        #expect(baseline.document.expandedText == segmentation.source)
        #expect(noChoices.document.expandedText == segmentation.source)
        #expect(noChoices.document.collapsedText == segmentation.source)
        #expect(baseline.decisions.count == segmentation.segments.count)
        #expect(noChoices.decisions.count == segmentation.segments.count)
        #expect(baseline.decisions.map(\.segment) == Array(segmentation.segments.indices))
    }

    @Test("Uma decisão por bloco, IDs em ordem e curta igual à frase", arguments: SegmentationFixtures.partitionInputs)
    func decisionsAreConsistent(_ source: String) {
        let segmentation = TextSegmenter.segment(source)
        let result = StretchFolder.foldWithFirstSentence(segmentation)

        var nextOrdinal = 0
        for (index, decision) in result.decisions.enumerated() {
            let segment = segmentation.segments[index]
            switch decision {
            case .folded(let segmentIndex, let stretchID, let choice):
                #expect(segmentIndex == index)
                #expect(segment.isFoldable)
                #expect(stretchID.path == [nextOrdinal])
                nextOrdinal += 1
                #expect(choice == SentenceChoice(sentenceID: segment.sentences[0].id, source: .firstSentence))
                let stretch = result.document.stretch(at: stretchID)
                #expect(stretch?.short == [.text(StretchFolder.shortForm(of: segment.sentences[0].text))])
                #expect(stretch?.long == [.text(segment.text)])
            case .unchanged(let segmentIndex, let reason):
                #expect(segmentIndex == index)
                #expect(!segment.isFoldable)
                switch reason {
                case .ineligibleKind(let kind): #expect(kind == segment.kind && kind != .paragraph)
                case .noSentence: #expect(segment.kind == .paragraph && segment.sentences.isEmpty)
                case .singleSentence: #expect(segment.kind == .paragraph && segment.sentences.count == 1)
                case .noChoice: Issue.record("a linha de base escolhe para todo bloco dobrável")
                }
            }
        }
        #expect(result.document.stretchIDs.count == nextOrdinal)
    }

    @Test("Texto vazio gera resultado vazio")
    func emptySource() throws {
        let result = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(""))
        #expect(result.decisions.isEmpty)
        #expect(result.document.nodes.isEmpty)
        #expect(result.document.expandedText == "")
        #expect(throws: FoldError.unknownSegment(0)) {
            try StretchFolder.fold(
                TextSegmenter.segment(""),
                choices: [0: SentenceChoice(sentenceID: SentenceID(segment: 0, index: 0), source: .firstSentence)]
            )
        }
    }

    // MARK: - Documentos realistas

    @Test("Documentos em português e inglês dobram só os parágrafos de duas frases ou mais")
    func realisticDocuments() {
        let portuguese = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(TextSegmenterTests.portugueseDocument))
        let english = StretchFolder.foldWithFirstSentence(TextSegmenter.segment(TextSegmenterTests.englishDocument))

        #expect(portuguese.document.stretchIDs.count == 3)
        #expect(portuguese.document.expandedText == TextSegmenterTests.portugueseDocument)
        #expect(portuguese.document.collapsedText.contains("Lisboa é a capital de Portugal.\n"))
        #expect(!portuguese.document.collapsedText.contains("Fica à beira do Tejo."))
        #expect(portuguese.document.collapsedText.contains("Dr. Silva recomenda o passeio.\n"))
        // Lista, citação, código e tabela ficam como estavam.
        #expect(portuguese.document.collapsedText.contains("- Torre de Belém. Patrimônio mundial."))
        #expect(portuguese.document.collapsedText.contains("```swift\nlet preço = 3.50\n```"))

        #expect(english.document.stretchIDs.count == 2)
        #expect(english.document.expandedText == TextSegmenterTests.englishDocument)
        #expect(english.document.collapsedText.contains("Version 2.1 is out.\n"))
        #expect(!english.document.collapsedText.contains("It is fast!"))
        #expect(english.document.collapsedText.contains("Note: see fig. 3 for details.\n"))
    }
}
