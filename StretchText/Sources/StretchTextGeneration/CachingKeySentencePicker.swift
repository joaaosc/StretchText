import Foundation
import StretchText

/// Reaproveita escolhas do modelo já conferidas e delega o resto ao seletor base.
///
/// Só `.selected(_, .model)` é gravado. Decisões determinísticas, falhas e
/// linhas de base nunca entram no cache, e acerto sempre sai como `.cache`.
public struct CachingKeySentencePicker: KeySentencePicker {
    private let base: any IdentifiableKeySentencePicker
    private let identity: KeySentencePickerIdentity
    private let cache: KeySentenceCache

    public init(base: some IdentifiableKeySentencePicker, cache: KeySentenceCache) {
        self.base = base
        self.identity = base.identity
        self.cache = cache
    }

    public func pick(from sentences: [Sentence], locale: Locale) async -> KeySentenceDecision {
        // Zero ou uma frase: decisão determinística do base, fora do cache.
        guard sentences.count >= 2 else {
            return await base.pick(from: sentences, locale: locale)
        }
        guard !Task.isCancelled else { return .failed(.cancelled) }

        let key = KeySentenceCacheKey(sentences: sentences, locale: locale, picker: identity)
        if let index = await cache.lookup(key, sentenceCount: sentences.count) {
            return .selected(sentenceID: sentences[index].id, source: .cache)
        }

        let decision = await base.pick(from: sentences, locale: locale)
        // Cancelada durante a consulta: o contrato pede `.cancelled`, mesmo que
        // o seletor base tenha respondido, e nada é gravado.
        guard !Task.isCancelled else { return .failed(.cancelled) }
        if case .selected(let id, .model) = decision,
           let index = sentences.firstIndex(where: { $0.id == id })
        {
            await cache.store(
                KeySentenceCache.Entry(sentenceIndex: index, sentenceCount: sentences.count),
                for: key
            )
        }
        return decision
    }
}
