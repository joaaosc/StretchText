/// Linha de base determinística: escolhe sempre a primeira frase do bloco.
public struct FirstSentencePicker: Sendable {
    public init() {}

    /// Primeira frase, com `source: .firstSentence`, para bloco dobrável; `nil`
    /// para os demais.
    public func choose(in segment: Segment) -> SentenceChoice? {
        guard segment.isFoldable, let first = segment.sentences.first else { return nil }
        return SentenceChoice(sentenceID: first.id, source: .firstSentence)
    }
}
