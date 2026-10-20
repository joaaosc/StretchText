import Foundation
import StretchText
import Testing
@testable import StretchTextGeneration

/// O exemplo do README para `StretchTextGeneration`. O seletor do modelo é só
/// construído; a montagem roda com um seletor roteirizado, sem runtime.
@Suite("Exemplo do README (geração)")
struct ReadmeGenerationExampleTests {
    @Test("O exemplo compila e a montagem guarda a origem de cada escolha")
    func example() async throws {
        let markdown = "O build falha às vezes. O motivo é um cache velho, que usa só o package.json como chave."
        _ = CachingKeySentencePicker(base: ModelKeySentencePicker(), cache: KeySentenceCache())

        let cache = KeySentenceCache()
        let scripted = ScriptedPicker { sentences in .selected(sentenceID: sentences[1].id, source: .model) }
        let picker = CachingKeySentencePicker(base: scripted, cache: cache)
        let folder = KeySentenceFolder(picker: picker, policy: .useFirstSentence)

        let result = try await folder.fold(TextSegmenter.segment(markdown), locale: Locale(identifier: "pt-BR"))
        #expect(result.fold.document.expandedText == markdown)
        #expect(result.fold.document.collapsedText == "O motivo é um cache velho, que usa só o package.json como chave.")
        guard case .folded(_, _, let choice) = result.fold.decisions[0] else {
            Issue.record("esperava bloco dobrado")
            return
        }
        #expect(choice.source == .model)

        // A mesma montagem de novo vem do cache, e a origem diz isso.
        let again = try await folder.fold(TextSegmenter.segment(markdown), locale: Locale(identifier: "pt-BR"))
        guard case .folded(_, _, let cached) = again.fold.decisions[0] else {
            Issue.record("esperava bloco dobrado")
            return
        }
        #expect(cached.source == .cache)
        #expect(await cache.statistics.hits == 1)
    }
}
