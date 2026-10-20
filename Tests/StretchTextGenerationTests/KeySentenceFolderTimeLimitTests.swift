import Foundation
import StretchText
import Testing
@testable import StretchTextGeneration

@Suite("Limite de tempo da montagem")
struct KeySentenceFolderTimeLimitTests {
    static let source = "Primeira frase. Segunda frase.\n\nOutro bloco. Com duas frases."
    static let locale = Locale(identifier: "pt-BR")

    @Test("Limite esgotado: blocos restantes não são consultados e caem na política", arguments: [
        FailurePolicy.useFirstSentence, .leaveUnchanged,
    ])
    func exhaustedLimit(policy: FailurePolicy) async throws {
        let log = CallLog()
        let picker = ScriptedPicker(log: log) { sentences in .selected(sentenceID: sentences[1].id, source: .model) }
        let folder = KeySentenceFolder(picker: picker, policy: policy, timeLimit: .zero)
        let segmentation = TextSegmenter.segment(Self.source)
        let result = try await folder.fold(segmentation, locale: Self.locale)

        #expect(await log.calls.isEmpty)
        #expect(result.pickerDecisions.isEmpty)
        #expect(result.fold.document.expandedText == Self.source)
        for index in [0, 2] {
            switch policy {
            case .useFirstSentence:
                guard case .folded(_, _, let choice) = result.fold.decisions[index] else {
                    Issue.record("bloco \(index) deveria dobrar pela linha de base")
                    continue
                }
                #expect(choice == SentenceChoice(
                    sentenceID: segmentation.segments[index].sentences[0].id,
                    source: .firstSentenceAfterFailure(.deadlineExceeded)
                ))
            case .leaveUnchanged:
                #expect(result.fold.decisions[index] == .unchanged(segment: index, reason: .selectionFailed(.deadlineExceeded)))
            }
        }
    }

    @Test("Com folga, o limite não muda nada")
    func generousLimit() async throws {
        let picker = ScriptedPicker { sentences in .selected(sentenceID: sentences[1].id, source: .model) }
        let folder = KeySentenceFolder(picker: picker, policy: .leaveUnchanged, timeLimit: .seconds(60))
        let result = try await folder.fold(TextSegmenter.segment(Self.source), locale: Self.locale)
        #expect(result.pickerDecisions.count == 2)
        #expect(result.fold.document.collapsedText == "Segunda frase.\n\nCom duas frases.")
    }
}
