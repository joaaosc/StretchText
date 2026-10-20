import Foundation
import StretchText
import Testing
@testable import StretchTextGeneration

@Suite("Seletor com cache")
struct CachingKeySentencePickerTests {
    static let portuguese = Locale(identifier: "pt_BR")
    static let sentences = makeSentences(["Primeira frase.", "Segunda frase.", "Terceira frase."])

    static var key: KeySentenceCacheKey {
        KeySentenceCacheKey(sentences: sentences, locale: portuguese, picker: .test)
    }

    // MARK: - Falta, gravação e acerto

    @Test("Na falta chama o seletor base, grava a escolha do modelo e devolve a decisão dele")
    func missCallsBaseAndStores() async {
        let log = CallLog()
        let cache = KeySentenceCache()
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(1)), cache: cache)

        let decision = await picker.pick(from: Self.sentences, locale: Self.portuguese)

        #expect(decision == .selected(sentenceID: Self.sentences[1].id, source: .model))
        #expect(await log.calls == [.init(sentenceIDs: Self.sentences.map(\.id), locale: Self.portuguese)])
        #expect(await cache.entries == [Self.key: .init(sentenceIndex: 1, sentenceCount: 3)])
        #expect(await cache.statistics == .init(hits: 0, misses: 1, stores: 1, rejected: 0))
    }

    @Test("Com a escolha gravada, a segunda chamada sai do cache sem chamar o base")
    func hitSkipsBase() async {
        let log = CallLog()
        let cache = KeySentenceCache()
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(1)), cache: cache)

        _ = await picker.pick(from: Self.sentences, locale: Self.portuguese)
        let second = await picker.pick(from: Self.sentences, locale: Self.portuguese)
        let third = await picker.pick(from: Self.sentences, locale: Self.portuguese)

        #expect(second == .selected(sentenceID: Self.sentences[1].id, source: .cache))
        #expect(third == second)
        #expect(await log.calls.count == 1)
        #expect(await cache.statistics == .init(hits: 2, misses: 1, stores: 1, rejected: 0))
    }

    @Test("Entrada restaurada de fora do processo também é um acerto")
    func restoredEntryIsAHit() async {
        let log = CallLog()
        let cache = KeySentenceCache(entries: [Self.key: .init(sentenceIndex: 2, sentenceCount: 3)])
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(0)), cache: cache)

        let decision = await picker.pick(from: Self.sentences, locale: Self.portuguese)

        #expect(decision == .selected(sentenceID: Self.sentences[2].id, source: .cache))
        #expect(await log.calls.isEmpty)
        #expect(await cache.statistics == .init(hits: 1, misses: 0, stores: 0, rejected: 0))
    }

    @Test("O acerto aponta para a frase na posição nova, não para o ID antigo")
    func hitUsesIDsOfTheCurrentSentences() async {
        let log = CallLog()
        let cache = KeySentenceCache()
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(1)), cache: cache)
        let texts = Self.sentences.map(\.text)

        _ = await picker.pick(from: makeSentences(texts, segment: 0), locale: Self.portuguese)
        let moved = await picker.pick(from: makeSentences(texts, segment: 7), locale: Self.portuguese)

        #expect(moved == .selected(sentenceID: SentenceID(segment: 7, index: 1), source: .cache))
        #expect(await log.calls.count == 1)
    }

    @Test("Texto, locale e identidade diferentes não compartilham decisões")
    func differentContextsDoNotShareDecisions() async {
        let log = CallLog()
        let cache = KeySentenceCache()
        let identity = KeySentencePickerIdentity.test
        let newerPrompt = KeySentencePickerIdentity(
            promptVersion: identity.promptVersion + 1, schemaVersion: identity.schemaVersion,
            generation: identity.generation, model: identity.model
        )
        let current = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(0)), cache: cache)
        let newer = CachingKeySentencePicker(
            base: ScriptedPicker(identity: newerPrompt, log: log, Rules.select(0)), cache: cache
        )

        _ = await current.pick(from: Self.sentences, locale: Self.portuguese)
        _ = await current.pick(from: Self.sentences, locale: Locale(identifier: "en_US"))
        _ = await current.pick(from: makeSentences(["Outra frase.", "E mais uma."]), locale: Self.portuguese)
        _ = await newer.pick(from: Self.sentences, locale: Self.portuguese)

        #expect(await log.calls.count == 4)
        #expect(await cache.entries.count == 4)
        #expect(await cache.statistics == .init(hits: 0, misses: 4, stores: 4, rejected: 0))
    }

    // MARK: - Menos de duas frases

    @Test("Menos de duas frases vai direto ao base, sem ler nem gravar no cache", arguments: [0, 1])
    func fewerThanTwoSentencesBypassesCache(_ count: Int) async {
        let texts = Array(Self.sentences.map(\.text).prefix(count))
        let sentences = makeSentences(texts)
        let expected: KeySentenceDecision = count == 0
            ? .noEligibleSentence
            : .selected(sentenceID: sentences[0].id, source: .onlySentence)
        let log = CallLog()
        // Uma entrada que acertaria, se o cache fosse lido.
        let trap = KeySentenceCacheKey(sentences: sentences, locale: Self.portuguese, picker: .test)
        let cache = KeySentenceCache(entries: [trap: .init(sentenceIndex: 0, sentenceCount: count)])
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log) { _ in expected }, cache: cache)

        let decision = await picker.pick(from: sentences, locale: Self.portuguese)
        _ = await picker.pick(from: sentences, locale: Self.portuguese)

        #expect(decision == expected)
        #expect(await log.calls.count == 2)
        #expect(await cache.statistics == KeySentenceCache.Statistics())
        #expect(await cache.entries == [trap: .init(sentenceIndex: 0, sentenceCount: count)])
    }

    // MARK: - Só o modelo é gravado

    /// Decisões do base que nunca podem entrar no cache.
    enum NotCacheable: String, CaseIterable, Sendable {
        case firstSentence
        case onlySentence
        case cache
        case firstSentenceAfterFailure
        case failure
        case noEligibleSentence
        case modelWithForeignID

        var rule: PickerRule {
            switch self {
            case .firstSentence: Rules.select(0, source: .firstSentence)
            case .onlySentence: Rules.select(0, source: .onlySentence)
            case .cache: Rules.select(1, source: .cache)
            case .firstSentenceAfterFailure: Rules.select(0, source: .firstSentenceAfterFailure(.modelTimeout))
            case .failure: { _ in .failed(.refusal) }
            case .noEligibleSentence: { _ in .noEligibleSentence }
            case .modelWithForeignID: { _ in .selected(sentenceID: SentenceID(segment: 9, index: 0), source: .model) }
            }
        }
    }

    @Test("Só .selected com origem .model é gravado; o resto passa sem alteração", arguments: NotCacheable.allCases)
    func onlyModelDecisionsAreStored(_ kind: NotCacheable) async {
        let log = CallLog()
        let cache = KeySentenceCache()
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, kind.rule), cache: cache)

        let first = await picker.pick(from: Self.sentences, locale: Self.portuguese)
        let second = await picker.pick(from: Self.sentences, locale: Self.portuguese)

        #expect(first == kind.rule(Self.sentences))
        #expect(second == first)
        #expect(await cache.entries.isEmpty)
        #expect(await log.calls.count == 2)
        #expect(await cache.statistics == .init(hits: 0, misses: 2, stores: 0, rejected: 0))
    }

    // MARK: - Cancelamento

    @Test("Cancelado antes de começar: .failed(.cancelled), sem tocar no cache nem chamar o base")
    func cancelledBeforeStart() async {
        let log = CallLog()
        // Uma entrada válida, que acertaria se o cache fosse lido.
        let cache = KeySentenceCache(entries: [Self.key: .init(sentenceIndex: 1, sentenceCount: 3)])
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(0)), cache: cache)

        let task = Task { () -> KeySentenceDecision in
            while !Task.isCancelled { await Task.yield() }
            return await picker.pick(from: Self.sentences, locale: Self.portuguese)
        }
        task.cancel()

        #expect(await task.value == .failed(.cancelled))
        #expect(await log.calls.isEmpty)
        #expect(await cache.statistics == KeySentenceCache.Statistics())
        #expect(await cache.entries.count == 1)
    }

    @Test("Cancelado durante o base: .failed(.cancelled) e nada gravado, mesmo se o base ignorar o cancelamento", arguments: [false, true])
    func cancelledDuringBaseDoesNotStore(_ honorsCancellation: Bool) async {
        let started = Gate()
        let log = CallLog()
        let cache = KeySentenceCache()
        let base = SleepingPicker(started: started, log: log, honorsCancellation: honorsCancellation)
        let picker = CachingKeySentencePicker(base: base, cache: cache)

        let task = Task { await picker.pick(from: Self.sentences, locale: Self.portuguese) }
        await started.wait()
        task.cancel()
        let decision = await task.value

        #expect(decision == .failed(.cancelled))
        #expect(await log.calls.count == 1)
        #expect(await cache.entries.isEmpty)
        #expect(await cache.statistics == .init(hits: 0, misses: 1, stores: 0, rejected: 0))
    }

    // MARK: - Entradas inválidas

    @Test("Entrada inválida é removida, conta como recusada e falta, e o base escolhe de novo", arguments: [
        KeySentenceCache.Entry(sentenceIndex: 0, sentenceCount: 5),
        KeySentenceCache.Entry(sentenceIndex: 3, sentenceCount: 3),
        KeySentenceCache.Entry(sentenceIndex: -2, sentenceCount: 3),
    ])
    func invalidEntryIsRemovedAndReplaced(_ stale: KeySentenceCache.Entry) async {
        let log = CallLog()
        let cache = KeySentenceCache(entries: [Self.key: stale])
        let picker = CachingKeySentencePicker(base: ScriptedPicker(log: log, Rules.select(2)), cache: cache)

        let decision = await picker.pick(from: Self.sentences, locale: Self.portuguese)

        #expect(decision == .selected(sentenceID: Self.sentences[2].id, source: .model))
        #expect(await log.calls.count == 1)
        #expect(await cache.entries == [Self.key: .init(sentenceIndex: 2, sentenceCount: 3)])
        #expect(await cache.statistics == .init(hits: 0, misses: 1, stores: 1, rejected: 1))
    }

    @Test("Entrada inválida cuja nova escolha não é do modelo deixa o cache sem a chave")
    func invalidEntryStaysRemovedWhenBaseDoesNotChooseWithModel() async {
        let cache = KeySentenceCache(entries: [Self.key: .init(sentenceIndex: 9, sentenceCount: 3)])
        let picker = CachingKeySentencePicker(
            base: ScriptedPicker(Rules.select(0, source: .firstSentenceAfterFailure(.rateLimited))),
            cache: cache
        )

        _ = await picker.pick(from: Self.sentences, locale: Self.portuguese)

        #expect(await cache.entries.isEmpty)
        #expect(await cache.statistics == .init(hits: 0, misses: 1, stores: 0, rejected: 1))
    }

    // MARK: - Concorrência

    @Test("Chamadas concorrentes ao mesmo cache terminam com uma entrada e contagens coerentes")
    func concurrentPicksShareOneCache() async {
        let count = 12
        let cache = KeySentenceCache()
        let picker = CachingKeySentencePicker(base: ScriptedPicker(Rules.select(2)), cache: cache)

        let decisions = await withTaskGroup(of: KeySentenceDecision.self) { group in
            for _ in 0..<count {
                group.addTask { await picker.pick(from: Self.sentences, locale: Self.portuguese) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(decisions.count == count)
        #expect(decisions.allSatisfy {
            $0 == .selected(sentenceID: Self.sentences[2].id, source: .model)
                || $0 == .selected(sentenceID: Self.sentences[2].id, source: .cache)
        })
        let statistics = await cache.statistics
        #expect(statistics.hits + statistics.misses == count)
        #expect(statistics.stores == statistics.misses)
        #expect(statistics.rejected == 0)
        #expect(await cache.entries == [Self.key: .init(sentenceIndex: 2, sentenceCount: 3)])
    }
}
