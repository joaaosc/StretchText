/// Monta o documento com trechos a partir da segmentação e das frases escolhidas.
///
/// A forma longa é sempre o bloco literal; a curta é uma frase do bloco. O
/// texto expandido do resultado é igual ao texto de origem.
public enum StretchFolder {
    /// Escolha já conferida: a frase existe no bloco dobrável.
    private struct Pick {
        let choice: SentenceChoice
        let sentence: Sentence
    }

    /// Dobra os blocos escolhidos. Confere todas as escolhas, em ordem crescente
    /// de bloco, antes de montar qualquer coisa. Bloco dobrável sem escolha fica
    /// `.unchanged(.noChoice)`.
    public static func fold(
        _ segmentation: Segmentation,
        choices: [Int: SentenceChoice]
    ) throws(FoldError) -> FoldResult {
        var picks: [Int: Pick] = [:]
        for (index, choice) in choices.sorted(by: { $0.key < $1.key }) {
            guard segmentation.segments.indices.contains(index) else {
                throw .unknownSegment(index)
            }
            let segment = segmentation.segments[index]
            guard segment.isFoldable else {
                throw .segmentNotFoldable(index)
            }
            guard choice.sentenceID.segment == index,
                  let sentence = segment.sentences.first(where: { $0.id == choice.sentenceID })
            else {
                throw .sentenceNotInSegment(choice.sentenceID, segment: index)
            }
            picks[index] = Pick(choice: choice, sentence: sentence)
        }
        return assemble(segmentation, picks: picks)
    }

    /// Linha de base: dobra todo bloco dobrável pela primeira frase.
    public static func foldWithFirstSentence(_ segmentation: Segmentation) -> FoldResult {
        let picker = FirstSentencePicker()
        var picks: [Int: Pick] = [:]
        for (index, segment) in segmentation.segments.enumerated() {
            guard let choice = picker.choose(in: segment),
                  let sentence = segment.sentences.first(where: { $0.id == choice.sentenceID })
            else { continue }
            picks[index] = Pick(choice: choice, sentence: sentence)
        }
        return assemble(segmentation, picks: picks)
    }

    /// A forma curta ocupa uma linha: cada sequência de espaços em branco com
    /// quebra de linha vira um único espaço. Nada mais muda.
    static func shortForm(of sentence: String) -> String {
        var result = ""
        var run = ""
        var runHasNewline = false

        func flushRun() {
            if runHasNewline {
                result.append(" ")
            } else {
                result.append(run)
            }
            run = ""
            runHasNewline = false
        }

        for character in sentence {
            if character.isWhitespace {
                run.append(character)
                if character.isNewline { runHasNewline = true }
            } else {
                flushRun()
                result.append(character)
            }
        }
        flushRun()
        return result
    }

    // MARK: - Montagem

    private static func assemble(_ segmentation: Segmentation, picks: [Int: Pick]) -> FoldResult {
        var nodes: [StretchNode] = []
        var decisions: [FoldDecision] = []
        var stretchCount = 0

        for (index, segment) in segmentation.segments.enumerated() {
            if let pick = picks[index] {
                let id = StretchID(validPath: [stretchCount])
                stretchCount += 1
                nodes.append(.stretch(Stretch(
                    short: [.text(shortForm(of: pick.sentence.text))],
                    long: [.text(segment.text)]
                )))
                decisions.append(.folded(segment: index, stretch: id, choice: pick.choice))
            } else {
                nodes.append(.text(segment.text))
                decisions.append(.unchanged(segment: index, reason: reason(for: segment)))
            }
        }
        return FoldResult(
            segmentation: segmentation,
            document: StretchDocument(nodes: nodes),
            decisions: decisions
        )
    }

    private static func reason(for segment: Segment) -> UnchangedReason {
        guard segment.kind == .paragraph else { return .ineligibleKind(segment.kind) }
        switch segment.sentences.count {
        case 0: return .noSentence
        case 1: return .singleSentence
        default: return .noChoice
        }
    }
}
