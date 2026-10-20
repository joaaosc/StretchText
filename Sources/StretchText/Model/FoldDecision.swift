/// Quem escolheu a frase que virou a forma curta.
public enum SelectionSource: Hashable, Sendable, Codable {
    /// Linha de base determinística: a primeira frase do bloco.
    case firstSentence
}

/// A frase escolhida para a forma curta de um bloco.
public struct SentenceChoice: Hashable, Sendable, Codable {
    public let sentenceID: SentenceID
    public let source: SelectionSource

    public init(sentenceID: SentenceID, source: SelectionSource) {
        self.sentenceID = sentenceID
        self.source = source
    }
}

/// Por que um bloco ficou como estava.
public enum UnchangedReason: Hashable, Sendable, Codable {
    /// Títulos, listas, código, tabelas, citações, separadores e espaços não
    /// viram trecho.
    case ineligibleKind(Segment.Kind)
    /// Parágrafo sem nenhuma frase (só pontuação ou símbolos).
    case noSentence
    /// Parágrafo de uma frase só: não há o que dobrar.
    case singleSentence
    /// Parágrafo elegível para o qual nenhuma escolha foi fornecida.
    case noChoice
}

/// O que aconteceu com cada bloco ao montar o documento.
public enum FoldDecision: Hashable, Sendable, Codable {
    case folded(segment: Int, stretch: StretchID, choice: SentenceChoice)
    case unchanged(segment: Int, reason: UnchangedReason)

    public var segment: Int {
        switch self {
        case .folded(let segment, _, _), .unchanged(let segment, _): segment
        }
    }
}

/// O documento montado e uma decisão por bloco, na ordem dos blocos.
public struct FoldResult: Hashable, Sendable, Codable {
    public let segmentation: Segmentation
    public let document: StretchDocument
    public let decisions: [FoldDecision]

    public init(segmentation: Segmentation, document: StretchDocument, decisions: [FoldDecision]) {
        self.segmentation = segmentation
        self.document = document
        self.decisions = decisions
    }
}

/// Escolha recusada pelo ``StretchFolder``: a frase precisa existir no bloco.
public enum FoldError: Error, Hashable, Sendable {
    /// A escolha aponta para um bloco que não existe.
    case unknownSegment(Int)
    /// A escolha aponta para um bloco que não pode virar trecho.
    case segmentNotFoldable(Int)
    /// A frase não pertence ao bloco indicado.
    case sentenceNotInSegment(SentenceID, segment: Int)
}
