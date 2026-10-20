import Foundation
import StretchText
import Testing
@testable import StretchTextGeneration

@Suite("Cache de decisões: chave e armazenamento")
struct KeySentenceCacheTests {
    static let portuguese = Locale(identifier: "pt_BR")
    static let texts = ["Primeira frase.", "Segunda frase."]

    static func key(
        _ texts: [String] = texts,
        locale: Locale = portuguese,
        picker: KeySentencePickerIdentity = .test,
        segmenterVersion: Int = TextSegmenter.version
    ) -> KeySentenceCacheKey {
        KeySentenceCacheKey(
            sentences: makeSentences(texts),
            locale: locale,
            picker: picker,
            segmenterVersion: segmenterVersion
        )
    }

    // MARK: - Hash do conteúdo

    @Test("O hash tem vetores fixos: tamanho em 8 bytes big-endian e bytes UTF-8 de cada frase", arguments: [
        ([String](), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        (["Primeira frase.", "Segunda frase."], "84f0ee51c0b72dd357e5d7573958f1be03e7e678e053ed869ba3471c787ed7bf"),
        // Acentos e emoji: o tamanho conta bytes UTF-8 (14 e 5), não caracteres.
        (["A\u{E7}\u{FA}car \u{1F600}.", "Ol\u{E1}."], "e5c9a935a1b5072f80bf95ccd7be5b7f75d758e2d429a571af95a9c8a4148f45"),
    ])
    func fixedHashVectors(_ texts: [String], _ expected: String) {
        #expect(Self.key(texts).contentHash == expected)
    }

    @Test("O hash é hexadecimal minúsculo de 64 caracteres")
    func hashFormat() {
        let hash = Self.key().contentHash
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("O tamanho de cada frase separa fronteiras diferentes")
    func hashFramingSeparatesBoundaries() {
        #expect(Self.key(["ab", "c"]).contentHash != Self.key(["a", "bc"]).contentHash)
        #expect(Self.key(["abc"]).contentHash != Self.key(["ab", "c"]).contentHash)
        #expect(Self.key(["", "a"]).contentHash != Self.key(["a", ""]).contentHash)
    }

    // MARK: - A chave muda com cada campo

    @Test("A chave muda com o texto, a ordem e a quantidade de frases")
    func keyChangesWithContent() {
        let original = Self.key()
        let variants = [
            Self.key(["Primeira frase.", "Segunda frase!"]),
            Self.key(["Primeira frase", "Segunda frase."]),
            Self.key(["Segunda frase.", "Primeira frase."]),
            Self.key(["Primeira frase."]),
            Self.key(Self.texts + ["Terceira frase."]),
        ]
        for variant in variants {
            #expect(variant != original)
            #expect(variant.contentHash != original.contentHash)
        }
        #expect(Set(variants + [original]).count == variants.count + 1)
    }

    @Test("A chave muda com o locale e com a versão do segmentador")
    func keyChangesWithLocaleAndSegmenterVersion() {
        let original = Self.key()
        let otherLocale = Self.key(locale: Locale(identifier: "en_US"))
        let otherVersion = Self.key(segmenterVersion: TextSegmenter.version + 1)

        #expect(otherLocale != original)
        #expect(otherLocale.contentHash == original.contentHash)
        #expect(otherLocale.locale == "en-US")
        #expect(otherVersion != original)
        #expect(otherVersion.contentHash == original.contentHash)
        #expect(otherVersion.segmenterVersion == TextSegmenter.version + 1)
        #expect(otherLocale != otherVersion)
    }

    @Test("A chave muda com cada campo da identidade do seletor")
    func keyChangesWithEachIdentityField() {
        let identity = KeySentencePickerIdentity.test
        let variants: [KeySentencePickerIdentity] = [
            KeySentencePickerIdentity(
                promptVersion: identity.promptVersion + 1, schemaVersion: identity.schemaVersion,
                generation: identity.generation, model: identity.model
            ),
            KeySentencePickerIdentity(
                promptVersion: identity.promptVersion, schemaVersion: identity.schemaVersion + 1,
                generation: identity.generation, model: identity.model
            ),
            KeySentencePickerIdentity(
                promptVersion: identity.promptVersion, schemaVersion: identity.schemaVersion,
                generation: identity.generation + "+outra", model: identity.model
            ),
            KeySentencePickerIdentity(
                promptVersion: identity.promptVersion, schemaVersion: identity.schemaVersion,
                generation: identity.generation, model: identity.model + " (27.3)"
            ),
        ]
        let original = Self.key()
        let keys = variants.map { Self.key(picker: $0) }
        for (variant, key) in zip(variants, keys) {
            #expect(key != original, "identidade \(variant)")
            #expect(key.contentHash == original.contentHash)
            #expect(key.picker == variant)
        }
        #expect(Set(keys + [original]).count == keys.count + 1)
    }

    // MARK: - A chave não muda com o que não é conteúdo

    @Test("A chave ignora o SentenceID e a posição em bytes")
    func keyIgnoresSentenceIDAndRange() {
        let original = KeySentenceCacheKey(
            sentences: makeSentences(Self.texts, segment: 0),
            locale: Self.portuguese,
            picker: .test
        )
        let moved = KeySentenceCacheKey(
            sentences: makeSentences(Self.texts, segment: 42).map {
                Sentence(id: $0.id, text: $0.text, utf8Range: 1000..<1000 + $0.text.utf8.count)
            },
            locale: Self.portuguese,
            picker: .test
        )
        #expect(moved == original)
        #expect(moved.hashValue == original.hashValue)
    }

    @Test("O mesmo parágrafo em outra posição do documento tem a mesma chave")
    func keyIgnoresPositionInDocument() throws {
        let paragraph = "Esta frase se repete. Esta outra também."
        let atStart = TextSegmenter.segment("\(paragraph)\n")
        let afterHeading = TextSegmenter.segment("# Título\n\nOutro texto. Mais um.\n\n\(paragraph)\n")
        let first = try #require(atStart.segments.first { $0.isFoldable })
        let last = try #require(afterHeading.segments.last { $0.isFoldable })

        #expect(first.id != last.id)
        #expect(first.sentences.map(\.id) != last.sentences.map(\.id))
        let firstKey = KeySentenceCacheKey(sentences: first.sentences, locale: Self.portuguese, picker: .test)
        let lastKey = KeySentenceCacheKey(sentences: last.sentences, locale: Self.portuguese, picker: .test)
        #expect(firstKey == lastKey)
    }

    @Test("Formas equivalentes do mesmo locale geram a mesma chave")
    func localeIdentifierIsNormalized() {
        let underscore = Self.key(locale: Locale(identifier: "pt_BR"))
        let hyphen = Self.key(locale: Locale(identifier: "pt-BR"))
        #expect(underscore.locale == "pt-BR")
        #expect(underscore == hyphen)
    }

    @Test("A versão do segmentador por padrão é a do segmentador")
    func defaultSegmenterVersion() {
        let implicit = KeySentenceCacheKey(
            sentences: makeSentences(Self.texts), locale: Self.portuguese, picker: .test
        )
        #expect(implicit.segmenterVersion == TextSegmenter.version)
        #expect(implicit == Self.key())
    }

    // MARK: - Codable

    @Test("Chave e entrada fazem ida e volta em JSON")
    func codableRoundTrip() throws {
        let key = Self.key()
        let decodedKey = try JSONDecoder().decode(KeySentenceCacheKey.self, from: JSONEncoder().encode(key))
        #expect(decodedKey == key)

        let entry = KeySentenceCache.Entry(sentenceIndex: 1, sentenceCount: 3)
        let decodedEntry = try JSONDecoder().decode(KeySentenceCache.Entry.self, from: JSONEncoder().encode(entry))
        #expect(decodedEntry == entry)
    }

    @Test("Um dicionário persistido volta a servir como cache")
    func persistedEntriesRestoreCache() async throws {
        let key = Self.key()
        let other = Self.key(locale: Locale(identifier: "en_US"))
        let original = KeySentenceCache()
        await original.store(.init(sentenceIndex: 1, sentenceCount: 2), for: key)
        await original.store(.init(sentenceIndex: 0, sentenceCount: 2), for: other)

        let data = try JSONEncoder().encode(await original.entries)
        let decoded = try JSONDecoder().decode([KeySentenceCacheKey: KeySentenceCache.Entry].self, from: data)
        let restored = KeySentenceCache(entries: decoded)

        #expect(await restored.entries == original.entries)
        #expect(await restored.lookup(key, sentenceCount: 2) == 1)
        #expect(await restored.lookup(other, sentenceCount: 2) == 0)
    }

    // MARK: - Armazenamento e estatísticas

    @Test("Um cache novo está vazio e sem contagens")
    func emptyCache() async {
        let cache = KeySentenceCache()
        #expect(await cache.entries.isEmpty)
        #expect(await cache.statistics == KeySentenceCache.Statistics())
    }

    @Test("Falta, gravação e acerto contam nas estatísticas")
    func missStoreAndHit() async {
        let cache = KeySentenceCache()
        let key = Self.key()

        #expect(await cache.lookup(key, sentenceCount: 2) == nil)
        #expect(await cache.statistics == .init(hits: 0, misses: 1, stores: 0, rejected: 0))

        await cache.store(.init(sentenceIndex: 1, sentenceCount: 2), for: key)
        #expect(await cache.entries == [key: .init(sentenceIndex: 1, sentenceCount: 2)])
        #expect(await cache.statistics == .init(hits: 0, misses: 1, stores: 1, rejected: 0))

        #expect(await cache.lookup(key, sentenceCount: 2) == 1)
        #expect(await cache.lookup(key, sentenceCount: 2) == 1)
        #expect(await cache.statistics == .init(hits: 2, misses: 1, stores: 1, rejected: 0))
    }

    @Test("Chaves diferentes não compartilham entradas")
    func differentKeysDoNotShareEntries() async {
        let cache = KeySentenceCache()
        await cache.store(.init(sentenceIndex: 1, sentenceCount: 2), for: Self.key())

        #expect(await cache.lookup(Self.key(["Outra frase.", "Mais uma."]), sentenceCount: 2) == nil)
        #expect(await cache.lookup(Self.key(locale: Locale(identifier: "en_US")), sentenceCount: 2) == nil)
        #expect(await cache.lookup(Self.key(segmenterVersion: 99), sentenceCount: 2) == nil)
        #expect(await cache.statistics == .init(hits: 0, misses: 3, stores: 1, rejected: 0))
    }

    @Test("Gravar de novo na mesma chave troca a entrada", arguments: [0, 1])
    func storeOverwrites(_ index: Int) async {
        let cache = KeySentenceCache()
        let key = Self.key()
        await cache.store(.init(sentenceIndex: 1 - index, sentenceCount: 2), for: key)
        await cache.store(.init(sentenceIndex: index, sentenceCount: 2), for: key)

        #expect(await cache.entries.count == 1)
        #expect(await cache.lookup(key, sentenceCount: 2) == index)
        #expect(await cache.statistics.stores == 2)
    }

    @Test("Entrada incoerente é removida, recusada e conta como falta", arguments: [
        // Quantidade de frases diferente da gravada.
        (KeySentenceCache.Entry(sentenceIndex: 0, sentenceCount: 3), 2),
        (KeySentenceCache.Entry(sentenceIndex: 0, sentenceCount: 2), 3),
        // Índice fora do intervalo.
        (KeySentenceCache.Entry(sentenceIndex: 2, sentenceCount: 2), 2),
        (KeySentenceCache.Entry(sentenceIndex: -1, sentenceCount: 2), 2),
        (KeySentenceCache.Entry(sentenceIndex: Int.max, sentenceCount: 2), 2),
    ])
    func invalidEntryIsRejectedAndRemoved(_ entry: KeySentenceCache.Entry, _ sentenceCount: Int) async {
        let key = Self.key()
        let cache = KeySentenceCache(entries: [key: entry])

        #expect(await cache.lookup(key, sentenceCount: sentenceCount) == nil)
        #expect(await cache.entries.isEmpty)
        #expect(await cache.statistics == .init(hits: 0, misses: 1, stores: 0, rejected: 1))

        // Já removida: a leitura seguinte é falta simples, sem nova recusa.
        #expect(await cache.lookup(key, sentenceCount: sentenceCount) == nil)
        #expect(await cache.statistics == .init(hits: 0, misses: 2, stores: 0, rejected: 1))
    }

    @Test("Remover tudo esvazia as entradas e mantém as contagens")
    func removeAllKeepsStatistics() async {
        let cache = KeySentenceCache()
        let key = Self.key()
        await cache.store(.init(sentenceIndex: 0, sentenceCount: 2), for: key)
        #expect(await cache.lookup(key, sentenceCount: 2) == 0)

        await cache.removeAll()
        #expect(await cache.entries.isEmpty)
        #expect(await cache.statistics == .init(hits: 1, misses: 0, stores: 1, rejected: 0))
        #expect(await cache.lookup(key, sentenceCount: 2) == nil)
    }
}
